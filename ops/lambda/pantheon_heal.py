import json
import os
import boto3

SG = os.environ["SG_ID"]
PORT = int(os.environ.get("PORT", "22"))
TOKEN = os.environ["TOKEN"]
DESC = "pantheon-heal-v1"
ec2 = boto3.client("ec2")


def respond(status, payload):
    return {
        "statusCode": status,
        "headers": {"content-type": "application/json"},
        "body": json.dumps(payload),
    }


def handler(event, context):
    try:
        body = json.loads(event.get("body") or "{}")
    except Exception:
        body = {}

    token = body.get("token") or (event.get("headers") or {}).get("x-pantheon-token")
    if token != TOKEN:
        return respond(403, {"error": "forbidden"})

    ip = body.get("ip") or (event.get("requestContext", {}).get("http", {}) or {}).get("sourceIp")
    if not ip:
        return respond(400, {"error": "no source ip"})
    cidr = f"{ip}/32"

    perms = ec2.describe_security_groups(GroupIds=[SG])["SecurityGroups"][0]["IpPermissions"]
    existing = []
    for perm in perms:
        if perm.get("IpProtocol") == "tcp" and perm.get("FromPort") == PORT:
            for r in perm.get("IpRanges", []):
                existing.append({"CidrIp": r["CidrIp"]})
    if existing:
        ec2.revoke_security_group_ingress(
            GroupId=SG,
            IpPermissions=[{
                "IpProtocol": "tcp", "FromPort": PORT, "ToPort": PORT,
                "IpRanges": existing,
            }],
        )

    try:
        ec2.authorize_security_group_ingress(
            GroupId=SG,
            IpPermissions=[{
                "IpProtocol": "tcp", "FromPort": PORT, "ToPort": PORT,
                "IpRanges": [{"CidrIp": cidr, "Description": DESC}],
            }],
        )
    except ec2.exceptions.ClientError as exc:
        if exc.response["Error"]["Code"] != "InvalidPermission.Duplicate":
            raise
    return respond(200, {"ok": True, "cidr": cidr})
