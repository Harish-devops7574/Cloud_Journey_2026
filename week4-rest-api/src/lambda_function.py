import json
import os
import uuid
from decimal import Decimal

import boto3

dynamodb = boto3.resource("dynamodb")

CORS_HEADERS = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin": os.environ.get("ALLOWED_ORIGIN", "*"),
    "Access-Control-Allow-Headers": "Content-Type,Authorization,X-Api-Key",
    "Access-Control-Allow-Methods": "GET,POST,PUT,DELETE,OPTIONS",
}


def _default(o):
    if isinstance(o, Decimal):
        return int(o) if o % 1 == 0 else float(o)
    raise TypeError


def _response(status_code, body):
    return {
        "statusCode": status_code,
        "headers": CORS_HEADERS,
        "body": "" if body is None else json.dumps(body, default=_default),
    }


def lambda_handler(event, context):
    stage_vars = event.get("stageVariables") or {}
    table = dynamodb.Table(stage_vars.get("tableName", "Users"))
    method = event["httpMethod"]
    user_id = (event.get("pathParameters") or {}).get("id")

    try:
        if method == "GET" and not user_id:
            return _response(200, table.scan().get("Items", []))

        if method == "POST":
            data = json.loads(event.get("body") or "{}")
            data["userId"] = data.get("userId") or str(uuid.uuid4())
            table.put_item(Item=data)
            return _response(201, data)

        if method == "GET":
            item = table.get_item(Key={"userId": user_id}).get("Item")
            return _response(200, item) if item else _response(404, {"message": "Not found"})

        if method == "PUT" and user_id:
            data = json.loads(event.get("body") or "{}")
            data["userId"] = user_id
            table.put_item(Item=data)
            return _response(200, data)

        if method == "DELETE" and user_id:
            table.delete_item(Key={"userId": user_id})
            return _response(204, None)

        return _response(405, {"message": "Method not allowed"})
    except json.JSONDecodeError:
        return _response(400, {"message": "Invalid JSON body"})
