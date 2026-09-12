"""LifeOptimizer backend -- FastAPI PoC.

Receives ONLY emergency/incident metadata (scores, classification, location,
timestamp). It never receives raw facial frames, depth maps, video, or the
on-device personal baseline -- see the privacy notes in INTEGRATION_B.md.

Run locally:
    pip install -r requirements.txt
    uvicorn main:app --reload --host 0.0.0.0 --port 8000
"""

from __future__ import annotations

from dotenv import load_dotenv

load_dotenv()  # picks up backend/.env (Twilio credentials) if present -- see .env.example

from fastapi import FastAPI, HTTPException
from fastapi.responses import HTMLResponse

from models import (
    CircleMember,
    EmergencyPayload,
    EmergencyResponse,
    IncidentPayload,
    IncidentRecord,
    IncidentResponse,
    JoinCircleRequest,
    JoinCircleResponse,
    LocationUpdate,
)
from services import circle as circle_service
from services import emergency as emergency_service

app = FastAPI(title="LifeOptimizer Backend", version="0.1.0")


@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


@app.post("/incident", response_model=IncidentResponse)
def post_incident(payload: IncidentPayload) -> IncidentResponse:
    return emergency_service.record_incident(payload)


@app.post("/emergency", response_model=EmergencyResponse)
def post_emergency(payload: EmergencyPayload) -> EmergencyResponse:
    return emergency_service.trigger_emergency(payload)


@app.post("/incident/{incident_id}/cancel", response_model=IncidentRecord)
def cancel_incident(incident_id: str) -> IncidentRecord:
    record = emergency_service.cancel_incident(incident_id)
    if record is None:
        raise HTTPException(status_code=404, detail="incident not found")
    return record


@app.get("/incident/{incident_id}", response_model=IncidentRecord)
def get_incident(incident_id: str) -> IncidentRecord:
    record = emergency_service.get_incident(incident_id)
    if record is None:
        raise HTTPException(status_code=404, detail="incident not found")
    return record


@app.get("/incidents", response_model=list[IncidentRecord])
def get_incidents() -> list[IncidentRecord]:
    return emergency_service.list_incidents()


@app.post("/circle/{patient_id}/join", response_model=JoinCircleResponse)
def join_circle(patient_id: str, request: JoinCircleRequest) -> JoinCircleResponse:
    member = circle_service.join_circle(patient_id, request)
    return JoinCircleResponse(memberId=member.memberId)


@app.post("/circle/{patient_id}/members/{member_id}/location", response_model=CircleMember)
def update_circle_location(patient_id: str, member_id: str, location: LocationUpdate) -> CircleMember:
    member = circle_service.update_location(patient_id, member_id, location.latitude, location.longitude)
    if member is None:
        raise HTTPException(status_code=404, detail="circle member not found")
    return member


@app.get("/circle/{patient_id}/members", response_model=list[CircleMember])
def get_circle_members(patient_id: str) -> list[CircleMember]:
    return circle_service.list_members(patient_id)


@app.get("/dashboard", response_class=HTMLResponse)
def dashboard() -> str:
    """Minimal, unstyled judge-facing view of incoming incidents. Not meant
    to be pretty -- just enough to show something arrived."""

    rows = ""
    for incident in emergency_service.list_incidents():
        loc = (
            f"{incident.location.latitude:.4f}, {incident.location.longitude:.4f}"
            if incident.location
            else "n/a"
        )
        rows += f"""
        <tr>
          <td>{incident.incidentId}</td>
          <td>{incident.timestamp}</td>
          <td>{incident.classification}</td>
          <td>{incident.confidence:.2f}</td>
          <td>{loc}</td>
          <td>{'YES (SIMULATED)' if incident.emergencyTriggered else 'no'}</td>
          <td>{'NOTIFIED (SIMULATED)' if incident.contactNotified else '-'}</td>
        </tr>"""

    return f"""
    <html>
      <head><title>LifeOptimizer -- Incidents</title></head>
      <body style="font-family: sans-serif;">
        <h2>LifeOptimizer -- Incident Dashboard (demo only)</h2>
        <p>Emergency services: SIMULATED. Emergency contact: SIMULATED.</p>
        <table border="1" cellpadding="6" cellspacing="0">
          <tr>
            <th>Incident ID</th><th>Timestamp</th><th>Classification</th>
            <th>Confidence</th><th>Location</th><th>Emergency</th><th>Contact</th>
          </tr>
          {rows or '<tr><td colspan="7">No incidents yet</td></tr>'}
        </table>
      </body>
    </html>
    """
