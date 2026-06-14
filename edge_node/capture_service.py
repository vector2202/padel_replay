import cv2
import numpy as np
import time
import threading
from collections import deque
from datetime import datetime, timedelta, timezone
import shutil
import os
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from supabase import create_client, Client

import sys
import json

# --- CARGAR CONFIGURACIÓN ---
def load_config():
    # Detectar si estamos corriendo como un ejecutable (.exe o binario)
    if getattr(sys, 'frozen', False):
        # Si es un ejecutable, buscamos el config al lado del .exe
        base_path = os.path.dirname(sys.executable)
    else:
        # Si es script de python, buscamos al lado del .py
        base_path = os.path.dirname(os.path.abspath(__file__))
    
    config_path = os.path.join(base_path, "config.json")
    
    default_config = {
        "camera_url": "http://192.168.0.22:8080/video",
        "supabase_url": "https://cwubftnikhgbspndecoc.supabase.co",
        "supabase_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN3dWJmdG5pa2hnYnNwbmRlY29jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzM2NjksImV4cCI6MjA5MjcwOTY2OX0.Iej5JNLUipE2TYd1-3FRd0r1XdgBN2XIXIqgYtggptw",
        "court_id": None
    }
    
    # Si no existe el config.json, lo creamos para que el usuario pueda editarlo
    if not os.path.exists(config_path):
        print(f"\n[Sistema] No se encontró config.json. Creando plantilla en: {config_path}")
        try:
            with open(config_path, "w") as f:
                json.dump(default_config, f, indent=4)
            print("[Sistema] Se ha creado un archivo 'config.json'.")
            print("[Sistema] POR FAVOR: Ábrelo, pon la IP de tu cámara y reinicia el programa.")
            # En un ejecutable, queremos que el usuario vea esto antes de que se cierre la ventana
            input("\nPresiona ENTER para salir...")
            sys.exit(0)
        except Exception as e:
            print(f"[Error] No se pudo crear el archivo de configuración: {e}")
            return default_config

    try:
        with open(config_path, "r") as f:
            print(f"[Sistema] Cargando configuración desde {config_path}")
            return json.load(f)
    except Exception as e:
        print(f"[Error] No se pudo leer config.json: {e}")
        return default_config

_config = load_config()

# --- FUNCIONES DE LOGO / OVERLAY ---
def _get_base_path():
    """Obtiene la ruta base según si es ejecutable o script."""
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    else:
        return os.path.dirname(os.path.abspath(__file__))

def load_logo(filename, target_width=None):
    """
    Carga una imagen PNG con canal alfa (transparencia).
    Si target_width se especifica, redimensiona manteniendo proporción.
    Retorna (bgr, alpha) o (None, None) si falla.
    """
    filepath = os.path.join(_get_base_path(), "images", filename)
    if not os.path.exists(filepath):
        print(f"[Logo] ADVERTENCIA: No se encontró {filepath}")
        return None, None
    
    img = cv2.imread(filepath, cv2.IMREAD_UNCHANGED)
    if img is None:
        print(f"[Logo] ADVERTENCIA: No se pudo cargar {filepath}")
        return None, None
    
    # Si la imagen no tiene canal alfa, crear uno totalmente opaco
    if img.shape[2] == 3:
        alpha = np.ones((img.shape[0], img.shape[1]), dtype=np.uint8) * 255
        img = np.dstack([img, alpha])
    
    # Redimensionar si se especifica target_width
    if target_width and target_width > 0:
        h, w = img.shape[:2]
        scale = target_width / w
        new_h = int(h * scale)
        img = cv2.resize(img, (target_width, new_h), interpolation=cv2.INTER_AREA)
    
    bgr = img[:, :, :3]
    alpha = img[:, :, 3].astype(np.float32) / 255.0
    return bgr, alpha

def overlay_logo(frame, logo_bgr, logo_alpha, x, y):
    """
    Superpone un logo con transparencia alfa sobre un frame.
    x, y = esquina superior izquierda del logo en el frame.
    """
    if logo_bgr is None or logo_alpha is None:
        return frame
    
    lh, lw = logo_bgr.shape[:2]
    fh, fw = frame.shape[:2]
    
    # Ajustar si el logo se sale del frame
    if x < 0: x = 0
    if y < 0: y = 0
    if x + lw > fw: lw = fw - x
    if y + lh > fh: lh = fh - y
    if lw <= 0 or lh <= 0:
        return frame
    
    # Región del frame donde va el logo
    roi = frame[y:y+lh, x:x+lw]
    logo_crop = logo_bgr[:lh, :lw]
    alpha_crop = logo_alpha[:lh, :lw]
    
    # Blending con alfa
    alpha_3ch = np.dstack([alpha_crop, alpha_crop, alpha_crop])
    blended = (alpha_3ch * logo_crop.astype(np.float32) + 
               (1.0 - alpha_3ch) * roi.astype(np.float32)).astype(np.uint8)
    frame[y:y+lh, x:x+lw] = blended
    return frame

# Precargar logos (se redimensionarán al tamaño final en save_clip_worker)
print("[Logo] Cargando logos...")
_logo_app_raw = cv2.imread(os.path.join(_get_base_path(), "images", "logo_app.png"), cv2.IMREAD_UNCHANGED)
_logo_club_raw = cv2.imread(os.path.join(_get_base_path(), "images", "logo_club.png"), cv2.IMREAD_UNCHANGED)
if _logo_app_raw is not None:
    print(f"[Logo] logo_app.png cargado ({_logo_app_raw.shape[1]}x{_logo_app_raw.shape[0]})")
else:
    print("[Logo] ADVERTENCIA: logo_app.png no encontrado o no se pudo cargar.")
if _logo_club_raw is not None:
    print(f"[Logo] logo_club.png cargado ({_logo_club_raw.shape[1]}x{_logo_club_raw.shape[0]})")
else:
    print("[Logo] ADVERTENCIA: logo_club.png no encontrado o no se pudo cargar.")

# ==========================================
# CONFIGURACIÓN DEL NODO EDGE
# ==========================================
RTSP_URL = _config["camera_url"]
BUFFER_SECONDS = 3  # Ajustado a 30s para producción
FPS = 30             
MAX_FRAMES = BUFFER_SECONDS * FPS

# Supabase config
SUPABASE_URL = _config["supabase_url"]
SUPABASE_KEY = _config["supabase_key"]
supabase: Client = create_client(SUPABASE_URL, SUPABASE_KEY)

COURT_ID = _config.get("court_id", None)

# Buffer circular y estado Global
frame_buffer = deque(maxlen=MAX_FRAMES)
stop_event = threading.Event()
cam_fps_global = FPS
width_global = 640
height_global = 480

# API FastAPI
app = FastAPI(title="Pladel Replay Edge Node")

# Configuración de CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def upload_to_supabase(filepath: str, duration: int, user_ids: list = None, court_id: str = None):
    print(f"[Supabase] Subiendo {filepath}...")
    filename = os.path.basename(filepath)
    try:
        # Subir a Storage
        with open(filepath, 'rb') as f:
            supabase.storage.from_("highlights").upload(
                path=filename,
                file=f,
                file_options={"content-type": "video/mp4"}
            )
        print("[Supabase] Video subido a Storage exitosamente.")
        
        # Obtener URL pública
        public_url = supabase.storage.from_("highlights").get_public_url(filename)
        
        # Insertar en tabla highlights con user_id y court_id
        if not user_ids:
            supabase.table("highlights").insert({
                "video_url_vertical": public_url,
                "duration_seconds": duration,
                "user_id": None,
                "court_id": court_id,
                "status": "ready"
            }).execute()
            print(f"[Supabase] Registro creado sin usuario asignado en cancha: {court_id}")
        else:
            insert_data = [
                {
                    "video_url_vertical": public_url,
                    "duration_seconds": duration,
                    "user_id": uid,
                    "court_id": court_id,
                    "status": "ready"
                }
                for uid in user_ids
            ]
            supabase.table("highlights").insert(insert_data).execute()
            print(f"[Supabase] Registro(s) creado(s) para usuario(s): {user_ids} en cancha: {court_id}")
        
        # BORRAR ARCHIVO LOCAL para no ocupar espacio
        if os.path.exists(filepath):
            os.remove(filepath)
            print(f"[Sistema] Archivo local {filepath} eliminado para liberar espacio.")
            
    except Exception as e:
        print(f"[Supabase Error] Falló la subida/registro: {e}")
        # También intentamos borrar si falló para no acumular basura
        if os.path.exists(filepath):
            os.remove(filepath)

def save_clip_worker(frames_to_save, fps, width, height, user_ids=None, court_id=None):
    """
    Consumidor: Hace recorte 9:16, guarda y sube.
    """
    if not frames_to_save:
        print("[Escritura] Buffer vacío.")
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_filename = f"highlight_{timestamp}.mp4"
    
    # --- LÓGICA DE RECORTE 9:16 ---
    new_width = (height * 9) // 16
    start_x = (width - new_width) // 2
    end_x = start_x + new_width
    
    target_h = 1280
    target_w = 720
    
    print(f"\n[Escritura] Recortando a 9:16 y guardando en {output_filename}...")
    start_time = time.time()

    fourcc = cv2.VideoWriter_fourcc(*'avc1')
    out = cv2.VideoWriter(output_filename, fourcc, fps, (target_w, target_h))

    # --- Preparar logos escalados para este tamaño de video ---
    logo_size = int(target_w * 0.18)  # Aumentado a 18% del ancho del video para mayor visibilidad
    margin = int(target_w * 0.04)     # 4% de margen desde los bordes para balancear el nuevo tamaño
    
    app_bgr, app_alpha = load_logo("logo_app.png", target_width=logo_size)
    club_bgr, club_alpha = load_logo("logo_club.png", target_width=logo_size)
    
    for frame in frames_to_save:
        cropped = frame[0:height, start_x:end_x]
        resized = cv2.resize(cropped, (target_w, target_h))
        
        # Logo App → esquina inferior izquierda
        if app_bgr is not None:
            app_y = target_h - app_bgr.shape[0] - margin
            resized = overlay_logo(resized, app_bgr, app_alpha, margin, app_y)
        
        # Logo Club → esquina inferior derecha
        if club_bgr is not None:
            club_x = target_w - club_bgr.shape[1] - margin
            club_y = target_h - club_bgr.shape[0] - margin
            resized = overlay_logo(resized, club_bgr, club_alpha, club_x, club_y)
        
        out.write(resized)

    out.release()
    elapsed = time.time() - start_time
    print(f"[Escritura] ¡Video procesado en {elapsed:.2f}s!\n")
    
    duration = int(len(frames_to_save) / fps)
    upload_to_supabase(output_filename, duration, user_ids, court_id)

@app.post("/trigger")
def trigger_clip(user_id: str = None, court_id: str = None):
    """
    Endpoint para disparar la grabación remotamente (desde la App o un botón físico).
    """
    effective_court_id = court_id or COURT_ID
    print(f"\n>>> TRIGGER DETECTADO PARA NODO. CANCHA EFECTIVA: {effective_court_id} <<<")
    
    user_ids = []
    if effective_court_id:
        try:
            one_hour_ago = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
            response = supabase.table("check_ins") \
                .select("user_id") \
                .eq("court_id", effective_court_id) \
                .gte("scanned_at", one_hour_ago) \
                .execute()
            
            if response.data:
                user_ids = list(set([row["user_id"] for row in response.data]))
                print(f"[Trigger] Jugadores detectados por check-in en la última hora: {user_ids}")
        except Exception as e:
            print(f"[Trigger Error] Error consultando check-ins: {e}")

    # Si se pasó un user_id específico en la petición HTTP (por ejemplo, desde el botón de la App),
    # nos aseguramos de que esté en la lista a procesar.
    if user_id and user_id not in user_ids:
        user_ids.append(user_id)

    frames_copy = list(frame_buffer)
    writer_thread = threading.Thread(
        target=save_clip_worker, 
        args=(frames_copy, cam_fps_global, width_global, height_global, user_ids, effective_court_id)
    )
    writer_thread.start()
    return {"status": "processing", "user_ids": user_ids, "court_id": effective_court_id}

def capture_loop():
    """
    Productor: Lee los frames de la cámara.
    """
    global cam_fps_global, width_global, height_global
    print(f"[Captura] Conectando a la cámara: {RTSP_URL}...")
    cap = cv2.VideoCapture(RTSP_URL)
    
    if not cap.isOpened():
        print("[Error] No se pudo abrir la cámara o el stream RTSP.")
        return

    cam_fps = cap.get(cv2.CAP_PROP_FPS)
    if cam_fps == 0 or cam_fps != cam_fps: 
        cam_fps = FPS
    
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    
    cam_fps_global = cam_fps
    width_global = width
    height_global = height
    
    print(f"[Captura] Conectado. Resolución: {width}x{height} a {cam_fps} FPS.")
    print(f"[Captura] Llenando buffer de {BUFFER_SECONDS}s (Max {MAX_FRAMES} frames).")

    while not stop_event.is_set():
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.1)
            continue
        
        frame_buffer.append(frame)
        
        preview = cv2.resize(frame, (640, 360))
        cv2.putText(preview, f"Buffer: {len(frame_buffer)}/{MAX_FRAMES}", (10, 30), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        cv2.putText(preview, "App/API o 'ESPACIO' para Guardar. 'q' SALIR.", (10, 60), 
                    cv2.FONT_HERSHEY_SIMPLEX, 0.6, (0, 0, 255), 2)
        
        cv2.imshow("Pladel Replay - Edge Node", preview)
        key = cv2.waitKey(1) & 0xFF
        
        if key == ord(' '): 
            print("\n>>> TRIGGER DETECTADO VÍA TECLADO <<<")
            user_ids = []
            if COURT_ID:
                try:
                    one_hour_ago = (datetime.now(timezone.utc) - timedelta(hours=1)).isoformat()
                    response = supabase.table("check_ins") \
                        .select("user_id") \
                        .eq("court_id", COURT_ID) \
                        .gte("scanned_at", one_hour_ago) \
                        .execute()
                    if response.data:
                        user_ids = list(set([row["user_id"] for row in response.data]))
                        print(f"[Teclado] Jugadores vinculados: {user_ids}")
                except Exception as e:
                    print(f"[Teclado Error] Error consultando check-ins: {e}")
            
            frames_copy = list(frame_buffer)
            writer_thread = threading.Thread(
                target=save_clip_worker, 
                args=(frames_copy, cam_fps, width, height, user_ids, COURT_ID)
            )
            writer_thread.start()

        elif key == ord('q'): 
            print("\n[Sistema] Cerrando aplicación...")
            stop_event.set()
            break

    cap.release()
    cv2.destroyAllWindows()

def heartbeat_loop():
    """
    Bucle que reporta el estado del nodo a Supabase periódicamente (cada 10 minutos).
    """
    if not COURT_ID:
        print("[Heartbeat] ADVERTENCIA: court_id no configurado en config.json. Reporte de estado desactivado.")
        return
    
    print(f"[Heartbeat] Iniciando bucle de monitoreo para la cancha: {COURT_ID}")
    while not stop_event.is_set():
        try:
            # 1. Determinar el estado de la cámara
            camera_ok = False
            if 'frame_buffer' in globals() and len(frame_buffer) > 0:
                # Si el buffer tiene frames, asumimos que está capturando
                camera_ok = True
                
            # 2. Métricas básicas del sistema
            total, used, free = shutil.disk_usage(".")
            disk_used_percent = (used / total) * 100
            
            status = "online" if camera_ok else "camera_offline"
            
            details = {
                "fps": cam_fps_global,
                "resolution": f"{width_global}x{height_global}",
                "disk_used_percent": round(disk_used_percent, 2),
                "free_space_gb": round(free / (1024**3), 2),
                "buffer_frames": len(frame_buffer)
            }
            
            supabase.table("courts").update({
                "last_heartbeat": datetime.now(timezone.utc).isoformat(),
                "node_status": status,
                "node_details": details
            }).eq("id", COURT_ID).execute()
            
            print(f"[Heartbeat] Reporte enviado. Estado: {status}. Disco libre: {details['free_space_gb']} GB")
            
        except Exception as e:
            print(f"[Heartbeat Error] Error al enviar reporte de estado: {e}")
            
        # Esperar 10 minutos (600 segundos) comprobando stop_event cada segundo
        for _ in range(600):
            if stop_event.is_set():
                break
            time.sleep(1)

def run_api():
    """Ejecuta el servidor FastAPI en el puerto 8000"""
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="info")

if __name__ == "__main__":
    print("=====================================")
    print(" INICIANDO PLADEL REPLAY EDGE NODE")
    print("=====================================")
    
    # 1. Iniciar servidor API en hilo secundario
    api_thread = threading.Thread(target=run_api, daemon=True)
    api_thread.start()
    
    # 2. Iniciar hilo de Heartbeat
    heartbeat_thread = threading.Thread(target=heartbeat_loop, daemon=True)
    heartbeat_thread.start()
    
    try:
        # 3. Iniciar captura de video en hilo principal (Requisito de OpenCV en Mac)
        capture_loop()
        
    except KeyboardInterrupt:
        print("\n[Sistema] Interrupción por teclado detectada.")
        stop_event.set()
        
    print("[Sistema] Programa finalizado.")
