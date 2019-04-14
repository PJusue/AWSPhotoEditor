import boto3
import mysql.connector
import os
from PIL import Image
import PIL.ImageOps
import json
UPLOAD_FOLDER = os.path.basename('/tmp')
sqs = boto3.client('sqs', region_name='us-west-2')
sns=boto3.client('sns',region_name='us-west-2')
client = boto3.client('rds', region_name='us-west-2')
bucket = boto3.client('s3')
db_url = client.describe_db_instances(DBInstanceIdentifier='mp2dbinstancereplica')[
    'DBInstances'][0]['Endpoint']['Address']

def read_database(id):
    cnx = mysql.connector.connect(
        user='pjusue', password='mp2pjusue', host=db_url, database='MP2')
    cursor = cnx.cursor()
    cursor.execute("SELECT * FROM MP2Data WHERE id={}".format(int(id)))
    for row in cursor:
        answer=row
    cursor.close() 
    cnx.close()
    return answer

def read_queue():
    queue_url = sqs.get_queue_url(QueueName='MP2queue')['QueueUrl']
    message=sqs.receive_message(QueueUrl=queue_url,WaitTimeSeconds=20)
    if 'Messages' in message:
        id=message['Messages'][0]['Body']
        sqs.delete_message(QueueUrl=queue_url,ReceiptHandle=message['Messages'][0]['ReceiptHandle'])

    else:
        id=0
    return id

def download_data(key):
    bucket.download_file('pjfimages-bucket',key,'/tmp/'+key)
def edit_image(name):
    image=Image.open('/tmp/'+name)
    new_image=PIL.ImageOps.flip(image)
    new_image.save('/tmp/edited_'+name)

def upload_image(name):
    f=os.path.join('/tmp','edited_'+name)
    new_url='https://s3-us-west-2.amazonaws.com/pjfimages-bucket/edited_'+name
    bucket.upload_file(f, 'pjfimages-bucket','edited_'+name,ExtraArgs={'ACL':'public-read'})
    return new_url
def send_sms(url,phone):
    sns.publish(PhoneNumber=phone,Message="Your photo is available at"+url)

if __name__ == "__main__":
    while(1):
        id=read_queue()
        if(id!=0):
            query=read_database(id)
            download_data(query[1])
            edit_image(query[1])
            new_url=upload_image(query[1])
            new_url=new_url.replace(' ','+')
            send_sms(new_url,query[2])