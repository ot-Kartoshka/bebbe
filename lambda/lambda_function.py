import boto3
import os
import json

def lambda_handler(event, context):
    s3 = boto3.client('s3', endpoint_url="http://localhost:4566")
    sqs = boto3.client('sqs', endpoint_url="http://localhost:4566")
    target_bucket = os.environ['TARGET_BUCKET']
    queue_url = os.environ['QUEUE_URL']

    for record in event['Records']:
        source_bucket = record['s3']['bucket']['name']
        key = record['s3']['object']['key']
        copy_source = {'Bucket': source_bucket, 'Key': key}

        s3.copy_object(
            Bucket=target_bucket,
            CopySource=copy_source,
            Key=key
        )

        message = {
            'file': key,
            'from': source_bucket,
            'to': target_bucket,
            'status': 'copied'
        }
        sqs.send_message(
            QueueUrl=queue_url,
            MessageBody=json.dumps(message)
        )

    return {"status": "done"}
