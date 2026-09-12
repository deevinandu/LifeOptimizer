"""Pydantic schemas for the LifeOptimizer backend.

These mirror the on-device `EmergencyEvent` / `DetectionResult` shapes
(see iOS/Models/AppModels.swift) exactly. The backend NEVER receives raw
facial/depth frames or the personal baseline -- only scores, a
classification label, a location, and a timestamp.
"""

from __future__ import annotations

from typing import List, Literal, Optional

from pydantic import BaseModel, Field

Classification = Literal["NORMAL", "MEDIUM", "HIGH"]


class Location(BaseModel):
    latitude: float
    longitude: float


class Signals(BaseModel):
    facial: float
    depth: Optional[float] = None
    motion: float
    temporal: Optional[float] = None
    speech: Optional[float] = None


class EmergencyPayload(BaseModel):
    incidentId: str
    timestamp: str
    confidence: float
    classification: Classification
    location: Optional[Location] = None
    signals: Signals
    patientName: Optional[str] = None
    contactName: Optional[str] = None
    contactPhone: Optional[str] = None
    contactCarrier: Optional[str] = None
    # Whoever this patient's Trusted Circle nearest-member lookup should key
    # off of -- see services/circle.py. Optional so existing callers/tests
    # that don't know about circles keep working unchanged.
    patientId: Optional[str] = None


# --- Trusted Circle ---------------------------------------------------------
#
# Real-time "who's near me" via Apple's Find My isn't accessible to
# third-party apps at all (no public API exposes another user's shared
# location, by design). This is a from-scratch, opt-in equivalent: a
# friend/family member's OWN copy of the app reports their location
# periodically (only while their app is open -- no special background
# entitlement), keyed to the patient's circle by a plain shareable code.


class JoinCircleRequest(BaseModel):
    name: str
    phone: Optional[str] = None
    carrier: Optional[str] = None
    # The joining device's own stable identity (its own patientId) -- lets
    # the backend recognize "this is the same device joining again" and
    # update the existing membership instead of creating a duplicate every
    # time (e.g. the app resuming a join on relaunch, or someone tapping
    # Join twice).
    memberDeviceId: Optional[str] = None


class JoinCircleResponse(BaseModel):
    memberId: str


class LocationUpdate(BaseModel):
    latitude: float
    longitude: float


class CircleMember(BaseModel):
    memberId: str
    name: str
    phone: Optional[str] = None
    carrier: Optional[str] = None
    latitude: Optional[float] = None
    longitude: Optional[float] = None
    lastUpdated: Optional[str] = None
    memberDeviceId: Optional[str] = None


class EmergencyResponse(BaseModel):
    status: Literal["emergency_triggered"] = "emergency_triggered"
    contactNotified: bool
    emergencyServices: Literal["SIMULATED"] = "SIMULATED"
    incidentId: str
    # Names of every Trusted Circle member who was actually texted --
    # ALL circle members get notified, not just whoever's nearest (that
    # was the original design; changed on request -- everyone in a
    # "trusted circle" should know, not just whoever happens to be close).
    circleMembersNotified: List[str] = []


class IncidentPayload(BaseModel):
    """Generic (non-emergency) incident/event log -- e.g. a NORMAL/MEDIUM
    detection the app wants recorded, or a benign-confirmation summary.
    Kept intentionally close to EmergencyPayload but does not imply an
    emergency was triggered."""

    incidentId: Optional[str] = None
    timestamp: str
    confidence: float
    classification: Classification
    location: Optional[Location] = None
    signals: Signals
    userResponse: Optional[Literal["confirmedOkay", "needsHelp", "timeout"]] = None


class IncidentRecord(BaseModel):
    incidentId: str
    timestamp: str
    confidence: float
    classification: Classification
    location: Optional[Location] = None
    signals: Signals
    emergencyTriggered: bool = False
    contactNotified: bool = False
    emergencyServices: Optional[Literal["SIMULATED"]] = None
    userResponse: Optional[Literal["confirmedOkay", "needsHelp", "timeout"]] = None


class IncidentResponse(BaseModel):
    status: Literal["incident_recorded"] = "incident_recorded"
    incidentId: str
