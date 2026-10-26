import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote

messages = []


class Handler(BaseHTTPRequestHandler):
    def reply(self, body):
        data = json.dumps(body).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/messages":
            self.reply(messages)
        elif self.path.endswith("/joined_rooms"):
            self.reply({"joined_rooms": []})
        else:
            self.reply({})

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        self.reply({"room_id": unquote(self.path.split("/rooms/")[-1].split("/")[0])})

    def do_PUT(self):
        content = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))))
        room = unquote(self.path.split("/rooms/")[1].split("/")[0])
        messages.append({"room": room, "content": content})
        self.reply({"event_id": f"${len(messages)}"})


ThreadingHTTPServer(("0.0.0.0", 6167), Handler).serve_forever()
