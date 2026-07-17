import os
import asyncio
import pxapi
from dotenv import load_dotenv

load_dotenv()

def get_px_connection():
    if os.getenv("DEV_MODE") == "true":
        return None

    token = os.getenv("PIXIE_API_TOKEN")
    cluster_id = os.getenv("PIXIE_CLUSTER_ID")

    # Safe asyncio setup for Flask threads
    loop = asyncio.new_event_loop()
    asyncio.set_event_loop(loop)

    client = pxapi.Client(token=token, server_url="getcosmic.ai")
    return client.connect_to_cluster(cluster_id)
