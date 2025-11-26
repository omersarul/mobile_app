import os, io, time, logging
os.environ['TFHUB_MODEL_LOAD_FORMAT'] = 'COMPRESSED' 
os.environ.setdefault('TFHUB_CACHE_DIR', os.path.expanduser('~/.cache/tfhub'))

from flask import Flask, request, send_file, jsonify
from flask_cors import CORS
import numpy as np
import tensorflow as tf
import tensorflow_hub as hub
from PIL import Image, ImageOps

try:
    gpus = tf.config.list_physical_devices('GPU')
    for g in gpus:
        tf.config.experimental.set_memory_growth(g, True)
except Exception:
    pass

app = Flask(__name__)
CORS(app)  
logging.basicConfig(level=logging.INFO)

HUB_URL = 'https://tfhub.dev/google/magenta/arbitrary-image-stylization-v1-256/2'
app.logger.info("Loading TF Hub model...")
hub_model = hub.load(HUB_URL)
app.logger.info("Model ready.")

def load_img_from_bytes(img_bytes: bytes, max_dim: int = 512) -> tf.Tensor:
    """
    Bytes -> RGB -> EXIF orientation fix -> uzun kenarı max_dim olacak şekilde
    küçült -> float32 [0,1] -> 4D [1,H,W,3]
    """
    img = Image.open(io.BytesIO(img_bytes)).convert('RGB')
    img = ImageOps.exif_transpose(img)  # orientation düzelt

    # oran koruyarak küçült
    img.thumbnail((max_dim, max_dim), Image.Resampling.LANCZOS)

    x = np.asarray(img, dtype=np.float32) / 255.0         # [H,W,3], 0..1
    return tf.convert_to_tensor(x)[tf.newaxis, ...]       # [1,H,W,3]

def tensor_to_png_bytes(t: tf.Tensor) -> io.BytesIO:
    """[1,H,W,3] veya [H,W,3] tensörü PNG'ye çevirir ve buffer döner."""
    if len(t.shape) == 4:
        t = tf.squeeze(t, axis=0)
    t = tf.clip_by_value(t, 0.0, 1.0)
    img = (t.numpy() * 255.0).astype('uint8')
    pil = Image.fromarray(img)
    buf = io.BytesIO()
    pil.save(buf, format='PNG')
    buf.seek(0)
    return buf


@app.get("/")
def index():
    return jsonify(ok=True, msg="Style Transfer API. POST /stylize"), 200

@app.get("/health")
def health():
    return "ok", 200

@app.post("/stylize")
def stylize():
    """
    Multipart form-data:
      - content: içerik görseli (required)
      - style:   stil görseli   (required)
      - max_dim: (opsiyonel, int) varsayılan 512
    """
    try:
        if 'content' not in request.files or 'style' not in request.files:
            return jsonify(error="fields 'content' and 'style' are required"), 400

        max_dim = int(request.form.get('max_dim', 512))
        content_bytes = request.files['content'].read()
        style_bytes   = request.files['style'].read()

        c = load_img_from_bytes(content_bytes, max_dim=max_dim)
        s = load_img_from_bytes(style_bytes,   max_dim=max_dim)

        t0 = time.time()
        stylized = hub_model(c, s)[0]
        dt = time.time() - t0
        app.logger.info("Stylize OK in %.2fs, shape=%s", dt, stylized.shape)

        buf = tensor_to_png_bytes(stylized)
        return send_file(buf, mimetype="image/png",
                         download_name="stylized.png",
                         as_attachment=False,
                         etag=False,
                         last_modified=None), 200

    except Exception as e:
        app.logger.exception("Stylize failed: %s", e)
        return jsonify(error=str(e)), 500

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=False)
