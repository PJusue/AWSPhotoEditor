import boto3
from PIL import Image
import PIL.ImageOps
from flask import Flask, render_template, request, send_from_directory, send_file, redirect, url_for
import mysql.connector
import os
import time
import sys
import subprocess
import memcache
import time
email = None
session = 0
app = Flask(__name__)
os.mkdir('uploads')
app = Flask(__name__, static_folder='')
UPLOAD_FOLDER = os.path.basename('uploads')
app.config['UPLOAD_FOLDER'] = UPLOAD_FOLDER
var = 0
memcach = boto3.client('elasticache', region_name='us-west-2')
sqs = boto3.client('sqs', region_name='us-west-2')
client = boto3.client('rds', region_name='us-west-2')
bucket = boto3.client('s3', region_name='us-west-2')
db_url_write = client.describe_db_instances(DBInstanceIdentifier='mp2dbinstance')[
    'DBInstances'][0]['Endpoint']['Address']
db_url_read = client.describe_db_instances(DBInstanceIdentifier='mp2dbinstancereplica')[
    'DBInstances'][0]['Endpoint']['Address']
hide = 0
#mc = memcache.Client([cache_url+':11211'],debug=1);
if os.path.exists("demofile.txt"):
    os.remove("session.txt")
cache_url = memcach.describe_cache_clusters(CacheClusterId='memcachemp3pjf')[
    'CacheClusters'][0]['ConfigurationEndpoint']['Address']
mc = memcache.Client([cache_url+':11211'], debug=1)


@app.route('/static/<path:path>')
def send_js(path):
    return send_from_directory('static', path)


def create_database():
    cnx = mysql.connector.connect(
        user='pjusue', password='mp2pjusue', host=db_url_write)
    cursor = cnx.cursor()
    cursor.execute("CREATE DATABASE IF NOT EXISTS MP2")
    cursor.close()
    cnx.close()


def create_datatable():
    cnx = mysql.connector.connect(
        user='pjusue', password='mp2pjusue', host=db_url_write, database='MP2')
    cursor = cnx.cursor()
    cursor.execute(
        "CREATE TABLE IF NOT EXISTS MP2Data (id INT PRIMARY KEY AUTO_INCREMENT, FILENAME VARCHAR(200) NOT NULL,PHONE_NUMBER VARCHAR(200) NOT NULL, S3URL VARCHAR(255) NOT NULL, EMAIL VARCHAR(200) NOT NULL,time VARCHAR(255) NOT NULL)")
    cnx.commit()
    cursor.close()
    cnx.close()


@app.route('/disable', methods=['GET', 'POST'])
def enablehide():
    global hide
    global var
    global email
    if request.method == 'POST':
        hide = 1
    return render_template('admin.html', var=var, hide=hide, email=email)


@app.route('/enable', methods=['GET', 'POST'])
def disablehide():
    global hide
    global var
    global email
    hide = 0
    return render_template('admin.html', var=var, email=email, hide=hide)


@app.route('/dump', methods=['GET','POST'])
def dump_database():
    os.popen("mysqldump -u %s -p%s -h %s -e --opt -c %s > /home/ubuntu/file.sql" %
                 ('pjusue', 'mp2pjusue', db_url_write, 'MP2'))
    return send_from_directory('/home/ubuntu/', 'file.sql')


def insert_data(url, name, phone, email):
    if email is None:
        f = open("session.txt", 'r')
        email = f.read()
        f.close()
    cnx = mysql.connector.connect(
        user='pjusue', password='mp2pjusue', host=db_url_write, database='MP2')
    cursor = cnx.cursor()
    cursor.execute("INSERT INTO MP2Data (FILENAME,PHONE_NUMBER,S3URL,EMAIL,time) VALUES('"+name+"', '" +
                   phone+"', '"+url.replace(' ', '+')+"', '"+email+"', '"+time.strftime('%Y-%m-%d-%H:%M:%S')+"')")
    id = cursor.lastrowid
    cnx.commit()
    cursor.close()
    cnx.close()
    email_comprobation = mc.get(email)
    if email_comprobation is not None:
        item = update_cache(email)
        mc.replace(email, item, 240)
    return id


def read_from_database(email):
    answer = mc.get(email)
    if answer is None:
        print('Reading SQL')
        cnx = mysql.connector.connect(
            user='pjusue', password='mp2pjusue', host=db_url_read, database='MP2')
        cursor = cnx.cursor(buffered=True)
        cursor.execute("SELECT * FROM MP2Data WHERE EMAIL='{}'".format(email))
        answer = cursor.fetchall()
        cursor.close()
        cnx.close()
        mc.set(email, answer, 240)
    else:
        print('Reading memcache')
    return answer


def update_cache(email):
    print('Reading SQL')
    cnx = mysql.connector.connect(
        user='pjusue', password='mp2pjusue', host=db_url_read, database='MP2')
    cursor = cnx.cursor(buffered=True)
    cursor.execute("SELECT * FROM MP2Data WHERE EMAIL='{}'".format(email))
    answer = cursor.fetchall()
    cursor.close()
    cnx.close()
    return answer


def download_data(key):
    url = key
    url = url.replace(' ', '+')
    new_url = '/home/ubuntu/pjusue/ITMO-544/MP3/pythonPrograms/static/'+url
    bucket.download_file('pjfimages-bucket', key, new_url)
    return url


@app.route('/endsession', methods=['GET', 'POST'])
def end_session():
    email = ''
    global session
    global hide
    global var
    if request.method == 'GET':
        os.remove("session.txt")
        var = 0
        session = 0
        print(var)
    return redirect('/form')


@app.route('/form', methods=['GET', 'POST'])
def upload_file():
    global var
    global hide
    global session
    global email
    if request.method == 'POST':
        image = request.files['file']
        name = image.filename
        name = name.replace("jpg", "png")
        phone = request.form['text']
        if var == 0:
            session = 1
            email = request.form['email']
            f = open("session.txt", 'w+')
            f.write(email)
            f.close()
            var = 1
        f = os.path.join(app.config['UPLOAD_FOLDER'], name)
        image.save(f)
        create_database()
        create_datatable()
        bucket.upload_file(f, 'pjfimages-bucket', name)
        url = 'https://s3-us-west-2.amazonaws.com/pjfimages-bucket/'+name
        id = insert_data(url, name, phone, email)
        queue_url = sqs.get_queue_url(QueueName='MP2queue')['QueueUrl']
        sqs.send_message(QueueUrl=queue_url, MessageBody=(str(id)))

    return render_template('imageupload.html', var=var, hide=hide, session=session, email=email)


def editimage(name):
    size = 1280, 1280
    image = Image.open(
        '/home/ubuntu/pjusue/ITMO-544/MP3/pythonPrograms/static/'+name)
    new_image = image.resize(size)
    new_image.save(
        '/home/ubuntu/pjusue/ITMO-544/MP3/pythonPrograms/static/'+name)


@app.route('/admin', methods=['GET', 'POST'])
def admin_page():
    global hide
    global email
    global var
    if request.method == 'POST':
        if request.form['block']:
            hide = 1
    return render_template('admin.html', var=var, hide=hide, email=email)


@app.route('/gallery', methods=['GET', 'POST'])
def show_images():
    images = []
    global session
    global email
    global var
    if request.method == 'GET' and session == 1:
        f = open("session.txt", 'r')
        email = f.read()
        f.close()
        database_rows = read_from_database(email)
        for row in database_rows:
            image = download_data(row[1])
            images.append(image)
            edited_name = "edited_"+row[1]
            edited_name = edited_name.replace('jpg', 'png')
            image = download_data(edited_name)
            images.append(image)
            send_js(images[0])
    return render_template('gallery.html', var=var, images=images, session=session, email=email)


if __name__ == "__main__":
    app.run(host='0.0.0.0', port='5000')
