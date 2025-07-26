import http.server
import socketserver

PORT = 8000
HandlerClass = http.server.SimpleHTTPRequestHandler

# Patch in the correct extensions
HandlerClass.extensions_map['.js'] = 'application/javascript'
HandlerClass.extensions_map['.mjs'] = 'application/javascript'

# Run the server (like `python -m http.server` does)
with socketserver.TCPServer(("", PORT), HandlerClass) as httpd:
    print("serving at port", PORT)
    httpd.serve_forever()
