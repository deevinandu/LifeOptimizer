"""SQLite-backed incident store + simulated emergency-contact/dispatch logic.

Hackathon PoC: SQLite is the only persistence, and only incidents/circle
data live there -- no Postgres/Redis/etc, per project scope rules. This
used to be a plain in-memory dict; see db.py for why that was replaced.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

import db
from models import (
    EmergencyPayload,
    EmergencyResponse,
    IncidentPayload,
    IncidentRecord,
    IncidentResponse,
)
from services import circle, notifications

_COLLECTION = "incidents"


def new_incident_id() -> str:
    return uuid.uuid4().hex[:8].upper()


def record_incident(payload: IncidentPayload) -> IncidentResponse:
    incident_id = payload.incidentId or new_incident_id()
    record = IncidentRecord(
        incidentId=incident_id,
        timestamp=payload.timestamp,
        confidence=payload.confidence,
        classification=payload.classification,
        location=payload.location,
        signals=payload.signals,
        emergencyTriggered=False,
        userResponse=payload.userResponse,
    )
    db.put(_COLLECTION, incident_id, record.model_dump(mode="json"))
    return IncidentResponse(incidentId=incident_id)


def trigger_emergency(payload: EmergencyPayload) -> EmergencyResponse:
    """Handle the emergency workflow: mark the incident, notify the
    configured contact, and "dispatch" emergency services.

    Emergency services (911/police/ambulance) dispatch is ALWAYS simulated
    -- see notifications.py for why that's a hard line, not a TODO.

    The personal emergency contact gets a REAL text via their carrier's
    email-to-SMS gateway when SMTP is configured (see
    services/notifications.py + .env.example); otherwise this falls back
    to the old simulated-only behavior so the backend still works out of
    the box with no setup at all.

    Additionally (not instead), if the patient has a Trusted Circle
    (payload.patientId) and a member is within range of the incident
    location, that member gets the same alert -- see services/circle.py."""

    if notifications.is_configured():
        contact_notified = notifications.send_contact_email_to_sms(payload)
    else:
        contact_notified = bool(payload.contactName or payload.contactPhone)

    circle_member_notified = False
    circle_member_name: Optional[str] = None
    if payload.patientId:
        nearest = circle.nearest_member(payload.patientId, payload.location)
        if nearest is not None:
            circle_member_name = nearest.name
            if notifications.is_configured():
                circle_member_notified = notifications.send_circle_member_alert(payload, nearest)

    record = IncidentRecord(
        incidentId=payload.incidentId,
        timestamp=payload.timestamp,
        confidence=payload.confidence,
        classification=payload.classification,
        location=payload.location,
        signals=payload.signals,
        emergencyTriggered=True,
        contactNotified=contact_notified,
        emergencyServices="SIMULATED",
    )
    db.put(_COLLECTION, payload.incidentId, record.model_dump(mode="json"))
    return EmergencyResponse(
        contactNotified=contact_notified,
        incidentId=payload.incidentId,
        circleMemberNotified=circle_member_notified,
        circleMemberName=circle_member_name,
    )


def get_incident(incident_id: str) -> Optional[IncidentRecord]:
    data = db.get(_COLLECTION, incident_id)
    return IncidentRecord.model_validate(data) if data else None


def list_incidents() -> list[IncidentRecord]:
    records = [IncidentRecord.model_validate(d) for d in db.list_all(_COLLECTION)]
    return sorted(records, key=lambda i: i.timestamp, reverse=True)


def cancel_incident(incident_id: str) -> Optional[IncidentRecord]:
    """Used by the app's "I'm Safe" button to record that the user cancelled
    an escalating alarm before real dispatch would have occurred."""

    record = get_incident(incident_id)
    if record is None:
        return None
    record.userResponse = "confirmedOkay"
    db.put(_COLLECTION, incident_id, record.model_dump(mode="json"))
    return record


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
