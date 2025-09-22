#!/usr/bin/env python3
"""
AWS Demo - ECS Container Application
Este script demuestra la ejecución de código Python en un container ECS/Fargate
"""

import json
import platform
import socket
import os
import sys
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import threading
import time
import boto3
from botocore.exceptions import NoCredentialsError

# Configuración
PORT = int(os.environ.get('PORT', 8080))
SERVICE_NAME = os.environ.get('SERVICE_NAME', 'Amazon ECS')

class DemoHTTPHandler(BaseHTTPRequestHandler):
    """Handler HTTP para servir la demo"""
    
    def do_GET(self):
        """Maneja peticiones GET"""
        if self.path == '/':
            self.send_response(200)
            self.send_header('Content-type', 'text/html')
            self.end_headers()
            self.wfile.write(self.get_html_response().encode())
        elif self.path == '/json':
            self.send_response(200)
            self.send_header('Content-type', 'application/json')
            self.end_headers()
            self.wfile.write(json.dumps(get_container_info(), indent=2).encode())
        elif self.path == '/health':
            self.send_response(200)
            self.send_header('Content-type', 'text/plain')
            self.end_headers()
            self.wfile.write(b'healthy')
        else:
            self.send_response(404)
            self.end_headers()
    
    def get_html_response(self):
        """Genera respuesta HTML"""
        data = get_container_info()
        
        html = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <title>ECS Container Demo - AWS Class</title>
            <meta http-equiv="refresh" content="30">
            <style>
                body {{
                    font-family: 'Amazon Ember', Arial, sans-serif;
                    background: linear-gradient(135deg, #146eb4 0%, #232f3e 100%);
                    color: white;
                    padding: 40px;
                    margin: 0;
                }}
                .container {{
                    max-width: 900px;
                    margin: 0 auto;
                    background: white;
                    color: #232f3e;
                    padding: 30px;
                    border-radius: 10px;
                    box-shadow: 0 4px 6px rgba(0,0,0,0.3);
                }}
                h1 {{
                    color: #146eb4;
                    border-bottom: 3px solid #ff9900;
                    padding-bottom: 10px;
                }}
                .metric {{
                    background: #f2f3f3;
                    padding: 15px;
                    margin: 10px 0;
                    border-left: 4px solid #146eb4;
                }}
                .docker-info {{
                    background: #e3f2fd;
                    padding: 15px;
                    margin: 10px 0;
                    border-left: 4px solid #2196f3;
                }}
                .timestamp {{
                    color: #666;
                    font-size: 0.9em;
                }}
                pre {{
                    background: #282c34;
                    color: #abb2bf;
                    padding: 15px;
                    border-radius: 5px;
                    overflow-x: auto;
                    font-size: 0.9em;
                }}
                .success {{
                    color: #48bb78;
                    font-weight: bold;
                }}
                .badge {{
                    display: inline-block;
                    padding: 3px 8px;
                    background: #ff9900;
                    color: white;
                    border-radius: 3px;
                    font-size: 0.8em;
                    margin-left: 10px;
                }}
                .refresh-note {{
                    position: absolute;
                    top: 20px;
                    right: 20px;
                    font-size: 0.8em;
                    color: #888;
                }}
            </style>
        </head>
        <body>
            <div class="refresh-note">Auto-refresh: 30s</div>
            <div class="container">
                <h1>🐳 ECS Container - Python Demo <span class="badge">FARGATE</span></h1>
                <p class="timestamp">Generated at: {data['timestamp']}</p>
                
                <div class="docker-info">
                    <h3>Container Information</h3>
                    <p><strong>Container ID:</strong> {data['container_info']['container_id']}</p>
                    <p><strong>Hostname:</strong> {data['container_info']['hostname']}</p>
                    <p><strong>Task ARN:</strong> {data['container_info'].get('task_arn', 'Not available')}</p>
                </div>
                
                <div class="metric">
                    <h3>Runtime Environment</h3>
                    <p><strong>Service:</strong> {data['service']}</p>
                    <p><strong>Platform:</strong> {data['system_info']['platform']}</p>
                    <p><strong>Python Version:</strong> {data['system_info']['python_version']}</p>
                    <p><strong>CPU Count:</strong> {data['system_info']['cpu_count']}</p>
                </div>
                
                <div class="metric">
                    <h3>Network Information</h3>
                    <p><strong>Container Port:</strong> {data['network']['port']}</p>
                    <p><strong>IP Address:</strong> {data['network']['ip_address']}</p>
                </div>
                
                <div class="metric">
                    <h3>Status</h3>
                    <p class="success">✅ {data['status']}</p>
                    <p>{data['message']}</p>
                </div>
                
                <h3>Environment Variables:</h3>
                <pre>{json.dumps(data['environment_vars'], indent=2)}</pre>
                
                <h3>API Endpoints:</h3>
                <ul>
                    <li><a href="/">/</a> - This HTML page</li>
                    <li><a href="/json">/json</a> - JSON response</li>
                    <li><a href="/health">/health</a> - Health check</li>
                </ul>
            </div>
        </body>
        </html>
        """
        return html
    
    def log_message(self, format, *args):
        """Override para reducir logs"""
        if '/health' not in args[0]:
            super().log_message(format, *args)

def get_container_info():
    """Obtiene información del container"""
    
    # Información del container
    container_info = {
        "container_id": socket.gethostname(),
        "hostname": socket.gethostname(),
    }
    
    # Intentar obtener Task ARN si estamos en ECS
    task_arn = os.environ.get('ECS_CONTAINER_METADATA_URI_V4')
    if task_arn:
        try:
            import urllib.request
            response = urllib.request.urlopen(f"{task_arn}/task", timeout=2)
            task_data = json.loads(response.read().decode('utf-8'))
            container_info['task_arn'] = task_data.get('TaskARN', 'Unknown')
            container_info['family'] = task_data.get('Family', 'Unknown')
        except:
            pass
    
    # Información del sistema
    system_info = {
        "platform": platform.platform(),
        "python_version": platform.python_version(),
        "processor": platform.processor() or "Container CPU",
        "cpu_count": os.cpu_count(),
    }
    
    # Información de red
    network = {
        "port": PORT,
        "ip_address": socket.gethostbyname(socket.gethostname())
    }
    
    # Variables de entorno relevantes (filtradas)
    env_vars = {
        k: v for k, v in os.environ.items() 
        if k.startswith(('AWS_', 'ECS_', 'SERVICE_', 'PORT'))
    }
    
    # Crear el objeto de datos completo
    data = {
        "timestamp": datetime.now().strftime("%Y-%m-%d %H:%M:%S"),
        "service": SERVICE_NAME,
        "container_info": container_info,
        "system_info": system_info,
        "network": network,
        "environment_vars": env_vars,
        "status": "RUNNING",
        "message": "Container ejecutándose correctamente en ECS/Fargate",
        "features": [
            "Servidor HTTP en puerto 8080",
            "Health checks disponibles",
            "Auto-refresh cada 30 segundos",
            "Endpoints JSON y HTML",
            "Información de Task ECS"
        ]
    }
    
    return data

def run_server():
    """Inicia el servidor HTTP"""
    server = HTTPServer(('', PORT), DemoHTTPHandler)
    print(f"\n{'='*50}")
    print(f"AWS ECS CONTAINER DEMO")
    print(f"{'='*50}")
    print(f"Server running on port {PORT}")
    print(f"Access points:")
    print(f"  - http://localhost:{PORT}/ (HTML)")
    print(f"  - http://localhost:{PORT}/json (JSON)")
    print(f"  - http://localhost:{PORT}/health (Health check)")
    print(f"{'='*50}\n")
    
    server.serve_forever()

def periodic_log():
    """Genera logs periódicos"""
    while True:
        time.sleep(60)  # Log cada minuto
        data = get_container_info()
        print(f"[{data['timestamp']}] Container Status: {data['status']}")
        print(f"  - Hostname: {data['container_info']['hostname']}")
        print(f"  - Port: {data['network']['port']}")
        print(f"  - Status: {data['status']}")

def main():
    """Función principal"""
    # Imprimir información inicial
    initial_data = get_container_info()
    print("\nContainer Information:")
    print(json.dumps(initial_data, indent=2))
    
    # Iniciar thread de logging periódico
    log_thread = threading.Thread(target=periodic_log, daemon=True)
    log_thread.start()
    
    # Iniciar servidor HTTP
    try:
        run_server()
    except KeyboardInterrupt:
        print("\n\nShutting down server...")
        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()