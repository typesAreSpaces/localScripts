#!/usr/bin/env python3

from __future__ import print_function
from apiclient.discovery import build
from httplib2 import Http
from oauth2client import file, client, tools

import imaplib
import os
import configparser

import requests

def notify(s):
    file=open("~/.unread_email", "w")
    file.write(s)
    file.close()

dirname = os.path.split(os.path.abspath(__file__))[0]
accounts = configparser.RawConfigParser()
accounts.read(os.path.abspath(dirname + '/accounts.ini'))
strFormatted = ""

def check_imap(imap_account):
    if imap_account["useSSL"] == "true":
        client = imaplib.IMAP4_SSL(imap_account["host"], int(imap_account["port"]))
    else:
        client = imaplib.IMAP4(imap_account["host"], int(imap_account["port"]))
    client.login(imap_account["login"], imap_account["password"])
    if "folder" in imap_account:
        client.select(imap_account["folder"])
    else:
        client.select()
    return len(client.search(None, 'UNSEEN')[1][0].split())

def check_gmail(gmail_account):
    SCOPES = 'https://www.googleapis.com/auth/gmail.readonly'
    credential_file = 'gmail/' + gmail_account + '.json'
    store = file.Storage(credential_file)
    credentials = store.get()
    if not credentials or credentials.invalid:
        flow = client.flow_from_clientsecrets('gmail/client_secret.json', SCOPES)
        credentials = tools.run_flow(flow, store)
    service = build('gmail', 'v1', http=credentials.authorize(Http()))
    results = service.users().messages().list(userId='me', q="is:unread").execute()
    return len(results["messages"])

try:
    url = "http://www.google.com"
    timeout = 1
    request = requests.get(url, timeout=timeout)
    for account in accounts:
        currentAccount = accounts[account]
        if account == "DEFAULT":
            continue
        if not currentAccount["icon"]:
            icon = accounts["DEFAULT"]["icon"]
        else:
            icon = currentAccount["icon"]
        if currentAccount['protocol'] == "GmailAPI":
            unread = check_gmail(account)
        else:
            unread = check_imap(currentAccount)
        strFormatted += icon + " " + str(unread)
        notify(strFormatted)
except (requests.ConnectionError, requests.Timeout) as exception:
    notify(strFormatted)
