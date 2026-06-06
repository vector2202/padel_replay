import cv2
import time
import threading
from collections import deque
from datetime import datetime
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
        "supabase_key": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImN3dWJmdG5pa2hnYnNwbmRlY29jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcxMzM2NjksImV4cCI6MjA5MjcwOTY2OX0.Iej5JNLUipE2TYd1-3FRd0r1XdgBN2XIXIqgYtggptw"
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

def upload_to_supabase(filepath: str, duration: int, user_id: str = None, court_id: str = None):
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
        data, count = supabase.table("highlights").insert({
            "video_url_vertical": public_url,
            "duration_seconds": duration,
            "user_id": user_id,
            "court_id": court_id,
            "status": "ready"
        }).execute()
        
        print(f"[Supabase] Registro creado para el usuario: {user_id} en cancha: {court_id}")
        
        # BORRAR ARCHIVO LOCAL para no ocupar espacio
        if os.path.exists(filepath):
            os.remove(filepath)
            print(f"[Sistema] Archivo local {filepath} eliminado para liberar espacio.")
            
    except Exception as e:
        print(f"[Supabase Error] Falló la subida: {e}")
        # También intentamos borrar si falló para no acumular basura
        if os.path.exists(filepath):
            os.remove(filepath)

def save_clip_worker(frames_to_save, fps, width, height, user_id=None, court_id=None):
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

    for frame in frames_to_save:
        cropped = frame[0:height, start_x:end_x]
        resized = cv2.resize(cropped, (target_w, target_h))
        out.write(resized)

    out.release()
    elapsed = time.time() - start_time
    print(f"[Escritura] ¡Video procesado en {elapsed:.2f}s!\n")
    
    duration = int(len(frames_to_save) / fps)
    upload_to_supabase(output_filename, duration, user_id, court_id)

@app.post("/trigger")
def trigger_clip(user_id: str = None, court_id: str = None):
    """
    Endpoint para que la App Flutter dispare la grabación remotamente.
    """
    print(f"\n>>> TRIGGER DETECTADO PARA USUARIO: {user_id} EN CANCHA: {court_id} <<<")
    frames_copy = list(frame_buffer)
    writer_thread = threading.Thread(
        target=save_clip_worker, 
        args=(frames_copy, cam_fps_global, width_global, height_global, user_id, court_id)
    )
    writer_thread.start()
    return {"status": "processing", "user_id": user_id, "court_id": court_id}

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
            frames_copy = list(frame_buffer)
            writer_thread = threading.Thread(
                target=save_clip_worker, 
                args=(frames_copy, cam_fps, width, height)
            )
            writer_thread.start()

        elif key == ord('q'): 
            print("\n[Sistema] Cerrando aplicación...")
            stop_event.set()
            break

    cap.release()
    cv2.destroyAllWindows()

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
    
    try:
        # 2. Iniciar captura de video en hilo principal (Requisito de OpenCV en Mac)
        capture_loop()
        
    except KeyboardInterrupt:
        print("\n[Sistema] Interrupción por teclado detectada.")
        stop_event.set()
        
    print("[Sistema] Programa finalizado.")
