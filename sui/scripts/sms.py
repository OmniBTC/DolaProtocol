import os
from pathlib import Path

from dotenv import load_dotenv
from twilio.rest import Client

load_dotenv(Path(__file__).parent.parent.joinpath('env/.env'))

account_sid = os.getenv("ACCOUNT_SID")
auth_token = os.getenv("AUTH_TOKEN")
sender = os.getenv("SENDER_PHONE_NUMBER")
receiver = os.getenv("HANDLER_PHONE_NUMBER")


def notify(msg: str):
    client = Client(account_sid, auth_token)

    client.messages.create(
        from_=sender,
        body=msg,
        to=receiver
    )
