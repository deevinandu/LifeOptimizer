"""In-memory incident store + simulated emergency-contact/dispatch logic.

Hackathon PoC: no database. Everything lives in a process-local dict, which
is fine for a 3-hour demo and explicitly keeps the backend free of
unnecessary infrastructure (no Postgres/Redis/etc, per project scope rules).
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

from models import (
    EmergencyPayload,
    EmergencyResponse,
    IncidentPayload,
    IncidentRecord,
    IncidentResponse,
)

_incidents: dict[str, IncidentRecord] = {}


def new_incident_id() -> str:
    return uuid.uuid4().hex[:8].upper()


def record_incident(payload: IncidentPayload) -> IncidentResponse:
    incident_id = payload.incidentId or new_incident_id()
    _incidents[incident_id] = IncidentRecord(
        incidentId=incident_id,
        timestamp=payload.timestamp,
        confidence=payload.confidence,
        classification=payload.classification,
        location=payload.location,
        signals=payload.signals,
        emergencyTriggered=False,
        userResponse=payload.userResponse,
    )
    return IncidentResponse(incidentId=incident_id)


def trigger_emergency(payload: EmergencyPayload) -> EmergencyResponse:
    """Simulate the emergency workflow: mark the incident, "notify" the
    configured contact, and "dispatch" emergency services. Nothing here
    contacts a real person or a real dispatch system -- see the PoC's
    privacy/limitations notes in INTEGRATION_B.md."""

    contact_notified = bool(payload.contactName or payload.contactPhone) or True
    _incidents[payload.incidentId] = IncidentRecord(
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
    return EmergencyResponse(
        contactNotified=contact_notified,
        incidentId=payload.incidentId,
    )


def get_incident(incident_id: str) -> Optional[IncidentRecord]:
    return _incidents.get(incident_id)


def list_incidents() -> list[IncidentRecord]:
    return sorted(_incidents.values(), key=lambda i: i.timestamp, reverse=True)


def cancel_incident(incident_id: str) -> Optional[IncidentRecord]:
    """Used by the app's "I'm Safe" button to record that the user cancelled
    an escalating alarm before real dispatch would have occurred."""

    record = _incidents.get(incident_id)
    if record is None:
        return None
    record.userResponse = "confirmedOkay"
    return record


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()
