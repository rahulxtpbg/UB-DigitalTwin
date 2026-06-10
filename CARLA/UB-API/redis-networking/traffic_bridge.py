#!/usr/bin/env python

import json
import socket
import time
import redis

REDIS_HOST = ""
REDIS_PORT = 0
REDIS_PASSWORD = ""
REDIS_CHANNEL = ""

UNITY_HOST = ""  # Change to Unity machine IP if on different machine
UNITY_PORT = 12345

TRAFFIC_MESSAGE_TYPE = 2

def main():
    r = redis.Redis(host=REDIS_HOST, port=REDIS_PORT, password=REDIS_PASSWORD)
    pubsub = r.pubsub()
    pubsub.subscribe(REDIS_CHANNEL)

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    unity_addr = (UNITY_HOST, UNITY_PORT)

    print(f"Subscribed to Redis channel '{REDIS_CHANNEL}'")
    print(f"Forwarding to Unity at {UNITY_HOST}:{UNITY_PORT}")

    for raw_message in pubsub.listen():
        if raw_message["type"] != "message":
            continue
        try:
            parsed = json.loads(raw_message["data"])

            if parsed.get("type") != TRAFFIC_MESSAGE_TYPE:
                continue
            if "vehicles" not in parsed:
                continue

            payload = {
                "vehicles": parsed["vehicles"],
                "timestamp": parsed["timestamp"]
            }

            data = json.dumps(payload).encode("utf-8")
            
            print(f"Sending {len(payload['vehicles'])} vehicles over the bridge")

            if len(data) > 60000:
                print(f"Warning: payload size {len(data)} bytes is close to UDP limit")

            sock.sendto(data, unity_addr)

        except Exception as e:
            print(f"Error: {e}")

if __name__ == "__main__":
    main()
