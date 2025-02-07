import json
import logging
import os
import boto3

# Setup logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)
handler = logging.StreamHandler()
handler.setLevel(logging.INFO)
formatter = logging.Formatter('%(asctime)s - %(name)s - %(levelname)s - %(message)s')
handler.setFormatter(formatter)
logger.addHandler(handler)

client = boto3.resource("dynamodb", region_name=os.getenv("REGION", "eu-west-1"))
dynamodb_table = client.Table(os.getenv("VisitsCounter"))

def handler(event, context):
    response = dynamodb_table.get_item(Key={"CounterName": "VisitsCounter"})

    if "Item" not in response:
        logger.info("No visits Counter in DynamoDB Table. Creating One Now...")
        dynamodb_table.put_item(
            Item={"CounterName": "VisitsCounter", "visits": 0},
        )
        currentVisitCount = 1
    else:
        currentVisitCount = int(response["Item"]["visits"]) + 1

    logger.info("Incrementing the visits Count by 1")
    dynamodb_table.update_item(
        Key={"CounterName": "VisitsCounter"},
        UpdateExpression="SET visits = visits + :newVisitor",
        ExpressionAttributeValues={":newVisitor": 1},
    )

    data = {"visits": currentVisitCount}

    response = {
        "statusCode": 200,
        "body": json.dumps(data),
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Headers": "Content-Type, Origin",
            "Access-Control-Allow-Origin": os.getenv("WEBSITE_CLOUDFRONT_DOMAIN", "*"),
            "Access-Control-Allow-Methods": "OPTIONS,POST,GET",
        },
    }

    return response
