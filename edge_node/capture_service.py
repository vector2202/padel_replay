import cv2
import numpy as np
import time
import threading
from collections import deque
from datetime import datetime, timedelta, timezone
import shutil
import os
import sys
import json
import logging
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
import uvicorn
from supabase import create_client, Client

# Detectar soporte de GPIO (Raspberry Pi)
try:
    from gpiozero import Button
    HAS_GPIO = True
except (ImportError, Exception):
    HAS_GPIO = False

# Configuración del sistema de Logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] [%(name)s] %(message)s",
    datefmt="%H:%M:%S"
)
logger = logging.getLogger("EdgeNode")

# --- CARGAR CONFIGURACIÓN ---
def load_config():
    if getattr(sys, 'frozen', False):
        base_path = os.path.dirname(sys.executable)
    else:
        base_path = os.path.dirname(os.path.abspath(__file__))
    
    config_path = os.path.join(base_path, "config.json")
    
    default_config = {
        "camera_url": "rtsp://admin:Sportsgram1@192.168.1.216:554/cam/realmonitor?channel=1&subtype=1",
        "supabase_url": "https://cwubftnikhgbspndecoc.supabase.co",
        "supabase_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN3dWJmdG5pa2hnYnNwbmRlY29jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzM2NjksImV4cCI6MjA5MjcwOTY2OX0.Iej5JNLUipE2TYd1-3FRd0r1XdgBN2XIXIqgYtggptw",
        "court_id": None,
        "buffer_seconds": 40
    }
    
    if not os.path.exists(config_path):
        logger.info(f"No se encontró config.json. Creando plantilla en: {config_path}")
        try:
            with open(config_path, "w") as f:
                json.dump(default_config, f, indent=4)
            logger.info("Se ha creado el archivo 'config.json'. Edita la IP de la cámara si es necesario.")
            input("\nPresiona ENTER para salir...")
            sys.exit(0)
        except Exception as e:
            logger.error(f"No se pudo crear el archivo de configuración: {e}")
            return default_config

    try:
        with open(config_path, "r") as f:
            logger.info(f"Cargando configuración desde {config_path}")
            return json.load(f)
    except Exception as e:
        logger.error(f"No se pudo leer config.json: {e}")
        return default_config

_config = load_config()

# --- FUNCIONES DE LOGO / OVERLAY ---
def _get_base_path():
    if getattr(sys, 'frozen', False):
        return os.path.dirname(sys.executable)
    else:
        return os.path.dirname(os.path.abspath(__file__))

def load_logo(filename, target_width=None):
    filepath = os.path.join(_get_base_path(), "images", filename)
    if not os.path.exists(filepath):
        logger.warning(f"No se encontró el logo en {filepath}")
        return None, None
    
    img = cv2.imread(filepath, cv2.IMREAD_UNCHANGED)
    if img is None:
        logger.warning(f"No se pudo cargar el logo desde {filepath}")
        return None, None
    
    if img.shape[2] == 3:
        alpha = np.ones((img.shape[0], img.shape[1]), dtype=np.uint8) * 255
        img = np.dstack([img, alpha])
    
    if target_width and target_width > 0:
        h, w = img.shape[:2]
        scale = target_width / w
        new_h = int(h * scale)
        img = cv2.resize(img, (target_width, new_h), interpolation=cv2.INTER_AREA)
    
    bgr = img[:, :, :3]
    alpha = img[:, :, 3].astype(np.float32) / 255.0
    return bgr, alpha

def overlay_logo(frame, logo_bgr, logo_alpha, x, y):
    if logo_bgr is None or logo_alpha is None:
        return frame
    
    lh, lw = logo_bgr.shape[:2]
    fh, fw = frame.shape[:2]
    
    if x < 0: x = 0
    if y < 0: y = 0
    if x + lw > fw: lw = fw - x
    if y + lh > fh: lh = fh - y
    if lw <= 0 or lh <= 0:
        return frame
    
    roi = frame[y:y+lh, x:x+lw]
    logo_crop = logo_bgr[:lh, :lw]
    alpha_crop = logo_alpha[:lh, :lw]
    
    alpha_3ch = np.dstack([alpha_crop, alpha_crop, alpha_crop])
    blended = (alpha_3ch * logo_crop.astype(np.float32) + 
               (1.0 - alpha_3ch) * roi.astype(np.float32)).astype(np.uint8)
    frame[y:y+lh, x:x+lw] = blended
    return frame

# ==========================================
# CONFIGURACIÓN DEL NODO EDGE
# ==========================================
RTSP_URL = _config["camera_url"]
BUFFER_SECONDS = _config.get("buffer_seconds", 40)
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

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

def upload_to_supabase(filepath: str, duration: int, user_ids: list = None, court_id: str = None):
    logger.info(f"Subiendo {filepath} a Supabase Storage...")
    filename = os.path.basename(filepath)
    try:
        with open(filepath, 'rb') as f:
            supabase.storage.from_("highlights").upload(
                path=filename,
                file=f,
                file_options={"content-type": "video/mp4"}
            )
        logger.info("Video subido a Storage exitosamente.")
        
        public_url = supabase.storage.from_("highlights").get_public_url(filename)
        
        if not user_ids:
            supabase.table("highlights").insert({
                "video_url_vertical": public_url,
                "duration_seconds": duration,
                "user_id": None,
                "court_id": court_id,
                "status": "ready"
            }).execute()
            logger.info(f"Registro creado sin usuario asignado en cancha: {court_id}")
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
            logger.info(f"Registro(s) creado(s) para usuario(s): {user_ids} en cancha: {court_id}")
        
        if os.path.exists(filepath):
            os.remove(filepath)
            logger.info(f"Archivo local {filepath} eliminado para liberar espacio.")
            
    except Exception as e:
        logger.error(f"Falló la subida/registro en Supabase: {e}")
        if os.path.exists(filepath):
            os.remove(filepath)

def save_clip_worker(frames_to_save, fps, width, height, user_ids=None, court_id=None):
    """
    Worker que recorta el buffer a 9:16, aplica los logos de la app y del club, y sube el clip.
    """
    if not frames_to_save:
        logger.warning("Intentando guardar pero el buffer está vacío.")
        return

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    output_filename = f"highlight_{timestamp}.mp4"
    
    # Recorte 9:16
    new_width = (height * 9) // 16
    start_x = (width - new_width) // 2
    end_x = start_x + new_width
    
    target_h = 1280
    target_w = 720
    
    logger.info(f"Procesando clip 9:16 ({len(frames_to_save)} frames) -> {output_filename}")
    start_time = time.time()

    temp_filename = f"temp_{output_filename}"
    
    fourcc = cv2.VideoWriter_fourcc(*'mp4v')
    out = cv2.VideoWriter(temp_filename, fourcc, fps, (target_w, target_h))

    # Logos escalados
    logo_size = int(target_w * 0.18)
    margin = int(target_w * 0.04)
    
    app_bgr, app_alpha = load_logo("logo_app.png", target_width=logo_size)
    club_bgr, club_alpha = load_logo("logo_club.png", target_width=logo_size)
    
    for frame in frames_to_save:
        cropped = frame[0:height, start_x:end_x]
        resized = cv2.resize(cropped, (target_w, target_h))
        
        # Logo App (inferior izquierda)
        if app_bgr is not None:
            app_y = target_h - app_bgr.shape[0] - margin
            resized = overlay_logo(resized, app_bgr, app_alpha, margin, app_y)
        
        # Logo Club (inferior derecha)
        if club_bgr is not None:
            club_x = target_w - club_bgr.shape[1] - margin
            club_y = target_h - club_bgr.shape[0] - margin
            resized = overlay_logo(resized, club_bgr, club_alpha, club_x, club_y)
        
        out.write(resized)

    out.release()
    
    # Transcodificación con FFmpeg (H.264 ultrafast)
    try:
        import subprocess
        logger.info("Transcodificando clip con FFmpeg (libx264, CRF 22)...")
        cmd = [
            'ffmpeg', '-y',
            '-i', temp_filename,
            '-c:v', 'libx264',
            '-preset', 'ultrafast',
            '-crf', '22',
            '-pix_fmt', 'yuv420p',
            output_filename
        ]
        subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
        if os.path.exists(temp_filename):
            os.remove(temp_filename)
    except Exception as e:
        logger.warning(f"FFmpeg no disponible o falló ({e}). Usando video crudo de OpenCV.")
        if os.path.exists(output_filename):
            os.remove(output_filename)
        shutil.move(temp_filename, output_filename)

    elapsed = time.time() - start_time
    logger.info(f"¡Video procesado en {elapsed:.2f}s!")
    
    duration = int(len(frames_to_save) / fps)
    upload_to_supabase(output_filename, duration, user_ids, court_id)

def trigger_capture(user_id: str = None, court_id: str = None, source: str = "UNKNOWN"):
    """
    Función centralizada para lanzar el procesamiento de un highlight desde cualquier origen
    (API HTTP, Botón Físico GPIO o Teclado).
    """
    effective_court_id = court_id or COURT_ID
    logger.info(f"TRIGGER ACTIVADO [{source}] - Cancha: {effective_court_id}")
    
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
                logger.info(f"Jugadores detectados por check-in activo: {user_ids}")
        except Exception as e:
            logger.error(f"Error consultando check-ins en Supabase: {e}")

    if user_id and user_id not in user_ids:
        user_ids.append(user_id)

    frames_copy = list(frame_buffer)
    writer_thread = threading.Thread(
        target=save_clip_worker, 
        args=(frames_copy, cam_fps_global, width_global, height_global, user_ids, effective_court_id)
    )
    writer_thread.start()
    return {"status": "processing", "user_ids": user_ids, "court_id": effective_court_id}

@app.post("/trigger")
def trigger_clip_endpoint(user_id: str = None, court_id: str = None):
    """Endpoint REST HTTP para disparar la grabación remotamente."""
    return trigger_capture(user_id=user_id, court_id=court_id, source="HTTP_API")

def capture_loop():
    """
    Bucle principal de captura de video (Productor).
    """
    global cam_fps_global, width_global, height_global
    logger.info(f"Conectando al stream RTSP de la cámara: {RTSP_URL}...")
    cap = cv2.VideoCapture(RTSP_URL)
    
    if not cap.isOpened():
        logger.error("No se pudo conectar a la cámara RTSP.")
        return

    cam_fps = cap.get(cv2.CAP_PROP_FPS)
    if cam_fps == 0 or cam_fps != cam_fps: 
        cam_fps = FPS
    
    width = int(cap.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT))
    
    cam_fps_global = cam_fps
    width_global = width
    height_global = height
    
    logger.info(f"Stream RTSP conectado. Resolución: {width}x{height} a {cam_fps:.1f} FPS.")
    logger.info(f"Buffer circular activo: {BUFFER_SECONDS}s ({MAX_FRAMES} frames máx).")

    while not stop_event.is_set():
        ret, frame = cap.read()
        if not ret:
            time.sleep(0.1)
            continue
        
        frame_buffer.append(frame)

    cap.release()

def heartbeat_loop():
    """
    Monitoreo periodico del estado del nodo hacia Supabase (cada 10 minutos).
    """
    if not COURT_ID:
        logger.warning("court_id no configurado en config.json. Heartbeat desactivado.")
        return
    
    logger.info(f"Iniciando monitoreo Heartbeat para cancha: {COURT_ID}")
    while not stop_event.is_set():
        try:
            camera_ok = len(frame_buffer) > 0
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
            
            logger.info(f"Heartbeat enviado ({status}). Disco libre: {details['free_space_gb']} GB")
            
        except Exception as e:
            logger.error(f"Error enviando Heartbeat a Supabase: {e}")
            
        for _ in range(600):
            if stop_event.is_set():
                break
            time.sleep(1)

def button_listener_loop():
    """
    Escucha eventos del botón físico en el pin GPIO 18 de la Raspberry Pi.
    """
    if not HAS_GPIO:
        logger.info("gpiozero no disponible (entorno sin GPIO). Botón físico desactivado.")
        return

    BUTTON_PIN = 18
    logger.info(f"Inicializando escucha de botón físico en GPIO {BUTTON_PIN}...")

    try:
        button = Button(BUTTON_PIN, pull_up=True, bounce_time=0.3)
        button.when_pressed = lambda: trigger_capture(source="GPIO_BUTTON")
        
        while not stop_event.is_set():
            time.sleep(1)
            
    except Exception as e:
        logger.error(f"Error inicializando el botón físico GPIO: {e}")

def run_api():
    """Ejecuta el servidor de API FastAPI."""
    uvicorn.run(app, host="0.0.0.0", port=8000, log_level="warning")

if __name__ == "__main__":
    logger.info("=====================================")
    logger.info(" INICIANDO PLADEL REPLAY EDGE NODE")
    logger.info("=====================================")
    
    api_thread = threading.Thread(target=run_api, daemon=True)
    api_thread.start()
    
    heartbeat_thread = threading.Thread(target=heartbeat_loop, daemon=True)
    heartbeat_thread.start()
    
    button_thread = threading.Thread(target=button_listener_loop, daemon=True)
    button_thread.start()
    
    try:
        capture_loop()
    except KeyboardInterrupt:
        logger.info("Interrupción por teclado (Ctrl+C). Finalizando...")
        stop_event.set()
        
    logger.info("Servicio detenido correctamente.")
