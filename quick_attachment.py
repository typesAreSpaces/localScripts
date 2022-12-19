#!/usr/bin/python3

import sys

import smtplib, ssl
from getpass import getpass

from email import encoders
from email.mime.base import MIMEBase
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText

def send_email(email, attachment):
    port = 587  
    smtp_server = "smtp.office365.com"
    subject = "Quick Attachment"
    body = f"""
    Sent by quick_attachment.py"""
    sender_email = "jabelcastellanosjoo@unm.edu"
    password = getpass('Password: ')

    receiver_email = email
    print(f"Sending email to {email}")
        
    # Create a multipart message and set headers
    message = MIMEMultipart()
    message["From"] = sender_email
    message["To"] = receiver_email
    message["Subject"] = subject
    # message["Bcc"] = receiver_email  # Recommended for mass emails
        
    # Add body to email
    message.attach(MIMEText(body, "plain"))
        
    filename = attachment
        
    # Open PDF file in binary mode
    with open(filename, "rb") as attachment:
        # Add file as application/octet-stream
        # Email client can usually download this automatically as attachment
        part = MIMEBase("application", "octet-stream")
        part.set_payload(attachment.read())
        
    # Encode file in ASCII characters to send by email    
    encoders.encode_base64(part)
        
    # Add header as key/value pair to attachment part
    part.add_header(
        "Content-Disposition",
        f"attachment; filename= {filename}",
    )
        
    # Add attachment to message and convert message to string
    message.attach(part)
    text = message.as_string()
        
    # Log in to server using secure context and send email
    context = ssl.create_default_context()
    with smtplib.SMTP(smtp_server, port) as server:
        server.ehlo()  # Can be omitted
        server.starttls(context=context)
        server.ehlo()  # Can be omitted
        server.login(sender_email, password)
        server.sendmail(sender_email, receiver_email, text)

if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit(1)
    email = str(sys.argv[1])
    attachment = str(sys.argv[2])
    send_email(email, attachment)
