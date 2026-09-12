"""Pydantic schemas for the LifeOptimizer backend.

These mirror the on-device `EmergencyEvent` / `DetectionResult` shapes
(see iOS/Models/AppModels.swift) exactly. The backend NEVER receives raw
facial/depth frames or the personal baseline -- only scores, a
classification label, a location, and a timestamp.
"""

from __future__ import annotations

from typing import Literal, Optional

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


class EmergencyResponse(BaseModel):
    status: Literal["emergency_triggered"] = "emergency_triggered"
    contactNotified: bool
    emergencyServices: Literal["SIMULATED"] = "SIMULATED"
    incidentId: str


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
