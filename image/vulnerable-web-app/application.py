# vim: tabstop=8 expandtab shiftwidth=4 softtabstop=4
import os
import time
from hashlib import sha1
from flask import Flask, render_template, request, send_file
from werkzeug import secure_filename
import subprocess

from apparmor_utils import sandbox, enter_confinement

enter_confinement("vulnerable")
app = Flask(__name__)

base_dir = os.path.dirname(__file__)
app.config['UPLOAD_FOLDER'] = '/tmp/bsideslux18/uploads/'
app.config['RESULT_FOLDER'] = '/tmp/bsideslux18/converted/'
app.config['ALLOWED_EXTENSIONS'] = set(['png', 'svg', 'png', 'jpg'])
app.config['PROPAGATE_EXCEPTIONS'] = True

def load_config():
    app.config.from_pyfile(os.path.join(base_dir, 'config.prod.cfg'))

@app.before_first_request
@sandbox("needs_config_file_access")
def app_setup():
    print("[*] Loading config...")
    load_config()
    os.makedirs(app.config['UPLOAD_FOLDER'], mode=0o744, exist_ok=True)
    os.makedirs(app.config['RESULT_FOLDER'], mode=0o744, exist_ok=True)

def allowed_file(filename):
    return '.' in filename and \
           filename.rsplit('.', 1)[1] in app.config['ALLOWED_EXTENSIONS']

@app.route('/')
@sandbox("needs_html_templates")
def index():
    return render_template('index.html')


def save_user_file(ufile):
    # Make the filename safe, remove unsupported chars
    filename = secure_filename(ufile.filename)
    input_file_path = os.path.join(app.config['UPLOAD_FOLDER'], filename)
    output_file_path = os.path.join(app.config['RESULT_FOLDER'],
                                        sha1(("%s_%s" % (filename, time.time())).encode("utf-8")).hexdigest() + ".png")
    ufile.save(input_file_path)

    return input_file_path, output_file_path

@sandbox("needs_imagemagick")
def convert_user_file(input_path, output_path, scale_param):
    command = ["convert", input_path, "-resize", scale_param, output_path]
    convert_result = subprocess.call(command)
    if convert_result == 0:
        os.remove(input_path)
    return convert_result

@app.route('/convert', methods=['POST'])
def upload():
    # Get the name of the uploaded file
    ufile = request.files['file']
    scale_param = request.form['scale']
    # Check if the file is one of the allowed types/extensions
    if ufile and allowed_file(ufile.filename):
        input_file_path, output_file_path = save_user_file(ufile)
        convert_result = convert_user_file(input_file_path, output_file_path, scale_param)
        if convert_result == 0:
            return send_file(output_file_path, mimetype='image/png')
        else:
            return "Conversion failed", 400
