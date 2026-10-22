import socket
from flask import Flask, jsonify

app = Flask(__name__)

# La API es el puente front<->back: por eso conoce la DB por su IP interna.
DB_HOST = "172.28.20.20"
DB_PORT = 5432


@app.route("/ping")
def ping():
    return "API viva"


@app.route("/db")
def db():
    """Comprueba en vivo que la API alcanza la base de datos (red back)."""
    try:
        with socket.create_connection((DB_HOST, DB_PORT), timeout=3):
            return jsonify(db="alcanzable", host=DB_HOST, port=DB_PORT)
    except OSError as exc:
        return jsonify(db="inalcanzable", host=DB_HOST, port=DB_PORT,
                       error=str(exc)), 503


@app.route("/info")
def info():
    """Muestra las interfaces de red de la API (sus dos redes)."""
    return jsonify(host=socket.gethostname(), db_host=DB_HOST)


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
