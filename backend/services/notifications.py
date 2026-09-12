"""Real SMS notification to a user's own emergency contact, via their
carrier's email-to-SMS gateway.

Scope, deliberately: this sends a text to the *personal* emergency contact
the user configured in Settings. It never contacts real emergency services
(911/police/ambulance) -- that stays simulated everywhere in this codebase,
on purpose. Placing an actual call to real emergency dispatch from a
hackathon demo with synthetic detection data would be dangerous and is out
of scope, full stop.

Why email-to-SMS instead of a dedicated SMS API (Twilio, etc.): trial-tier
accounts on those APIs require a paid-account-only "Content Template" for
ANY custom message body, SMS included -- a hard platform restriction with
no workaround short of upgrading. Email-to-SMS has no such gate: it just
routes a plain email through the recipient's own carrier as a text,
using an email account (Gmail, etc.) you already have SMTP access to.
Delivery isn't as guaranteed as a real SMS API (some carriers rate-limit
or occasionally drop gateway mail), but it's genuinely unblocked.

Configuration is via environment variables (see `.env.example`). If unset,
`send_contact_email_to_sms` returns False without raising -- callers fall
back to the old simulated-only behavior, so the backend still works out
of the box with no setup at all.
"""

from __future__ import annotations

import os
import re
import smtplib
from email.mime.text import MIMEText
from typing import Optional

from models import CircleMember, EmergencyPayload

_SMTP_HOST = os.environ.get("SMTP_HOST")
_SMTP_PORT = int(os.environ.get("SMTP_PORT", "587"))
_SMTP_USERNAME = os.environ.get("SMTP_USERNAME")
_SMTP_PASSWORD = os.environ.get("SMTP_PASSWORD")
_SMTP_FROM_EMAIL = os.environ.get("SMTP_FROM_EMAIL") or _SMTP_USERNAME

# Email-to-SMS gateway domains for major US carriers.
_CARRIER_GATEWAYS = {
    "verizon": "vtext.com",
    "att": "txt.att.net",
    "tmobile": "tmomail.net",
    "sprint": "messaging.sprintpcs.com",
    "uscellular": "email.uscc.net",
    "googleFi": "msg.fi.google.com",
    "boost": "sms.myboostmobile.com",
    "cricket": "sms.cricketwireless.net",
    "metro": "mymetropcs.com",
}


def is_configured() -> bool:
    return bool(_SMTP_HOST and _SMTP_USERNAME and _SMTP_PASSWORD and _SMTP_FROM_EMAIL)


def _build_message(payload: EmergencyPayload) -> str:
    location_line = ""
    if payload.location is not None:
        maps_url = f"https://maps.google.com/?q={payload.location.latitude},{payload.location.longitude}"
        location_line = f"\nLocation: {maps_url}"

    who = payload.patientName or "Someone using LifeOptimizer"

    # ALL-CAPS header + repeated emoji: the only things we actually control
    # over a plain text message that make it visually stand out in a
    # notification preview -- there's no way to give it a distinct SOUND or
    # priority banner over SMS/email-gateway (that requires the recipient's
    # own phone to treat this sender specially; see the reply that
    # accompanies this code change for the actual way to get that).
    return (
        "🚨🚨 LIFEOPTIMIZER EMERGENCY ALERT 🚨🚨\n"
        f"{who} may be having a {payload.classification.lower()}-confidence "
        f"stroke-like event (confidence {payload.confidence:.0%}) at "
        f"{payload.timestamp}.{location_line}\n"
        "This is an automated alert from a hackathon prototype, not a "
        "medical diagnosis -- please check on them now."
    )


def send_email_to_sms(message: str, phone: Optional[str], carrier: Optional[str]) -> bool:
    """Route a real text to an arbitrary recipient through their carrier's
    email-to-SMS gateway via plain SMTP. Shared by the primary emergency
    contact and Trusted Circle members alike. Never raises; any failure is
    caught and logged, returning False so the emergency workflow always
    completes."""

    if not is_configured():
        print("[notifications] SMTP not configured (see .env.example) -- skipping email-to-SMS.")
        return False

    if not phone:
        print("[notifications] No phone number on file -- skipping email-to-SMS.")
        return False

    if not carrier:
        print("[notifications] No carrier on file -- can't route email-to-SMS gateway.")
        return False

    gateway_domain = _CARRIER_GATEWAYS.get(carrier)
    if gateway_domain is None:
        print(f"[notifications] Unknown carrier '{carrier}' -- skipping email-to-SMS.")
        return False

    digits = re.sub(r"\D", "", phone)
    # Most US gateways want a plain 10-digit number, no country code.
    if len(digits) == 11 and digits.startswith("1"):
        digits = digits[1:]
    if len(digits) != 10:
        print(f"[notifications] Phone '{phone}' isn't a valid 10-digit US number -- skipping.")
        return False

    to_address = f"{digits}@{gateway_domain}"

    try:
        mime_message = MIMEText(message)
        mime_message["Subject"] = "LifeOptimizer Alert"
        mime_message["From"] = _SMTP_FROM_EMAIL
        mime_message["To"] = to_address

        with smtplib.SMTP(_SMTP_HOST, _SMTP_PORT) as server:
            server.starttls()
            server.login(_SMTP_USERNAME, _SMTP_PASSWORD)
            server.sendmail(_SMTP_FROM_EMAIL, [to_address], mime_message.as_string())

        print(f"[notifications] Email-to-SMS sent to {to_address}")
        return True
    except Exception as exc:  # noqa: BLE001 -- must never crash the emergency endpoint
        print(f"[notifications] Email-to-SMS failed: {exc}")
        return False


def send_contact_email_to_sms(payload: EmergencyPayload) -> bool:
    """Text the primary emergency contact configured in Settings."""
    return send_email_to_sms(_build_message(payload), payload.contactPhone, payload.contactCarrier)


def send_circle_member_alert(payload: EmergencyPayload, member: CircleMember) -> bool:
    """Text a Trusted Circle member who was found nearby -- same alert, but
    framed as "you're nearby" rather than "you're the designated contact"
    so it's clear why they're getting it."""
    message = (
        _build_message(payload)
        + f"\nYou're getting this because you're nearby and in {payload.patientName or 'their'} "
          "Trusted Circle on LifeOptimizer."
    )
    return send_email_to_sms(message, member.phone, member.carrier)
