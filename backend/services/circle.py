"""Trusted Circle: SQLite-backed, opt-in "who's nearby" lookup.

This exists because Apple's Find My does not expose any public API for a
third-party app to read who has shared their location with a user, or
those people's coordinates -- that data is private to Apple's own app,
full stop (see the reply that motivated this file for the long version).

This is a from-scratch, consent-based equivalent scoped to this app only:
a friend/family member explicitly joins a specific patient's circle (by
entering a code the patient shares, or scanning their QR code), and their
OWN copy of the app reports their current location continuously in the
background (via CircleLocationTracker) -- no reading of anyone's data
outside this app's own users.
"""

from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Optional

import db
from models import CircleMember, JoinCircleRequest


def _collection(patient_id: str) -> str:
    return f"circle_members:{patient_id}"


def join_circle(patient_id: str, request: JoinCircleRequest) -> CircleMember:
    # Same device joining the same circle again (relaunch resuming a join,
    # a double-tap, re-scanning the same QR) updates its existing
    # membership instead of cloning a new one -- keyed on the joining
    # device's own stable patientId, not on name/phone (which could
    # legitimately change).
    if request.memberDeviceId:
        for existing in list_members(patient_id):
            if existing.memberDeviceId == request.memberDeviceId:
                existing.name = request.name
                existing.phone = request.phone
                existing.carrier = request.carrier
                db.put(_collection(patient_id), existing.memberId, existing.model_dump(mode="json"))
                return existing

    member = CircleMember(
        memberId=uuid.uuid4().hex[:8],
        name=request.name,
        phone=request.phone,
        carrier=request.carrier,
        memberDeviceId=request.memberDeviceId,
    )
    db.put(_collection(patient_id), member.memberId, member.model_dump(mode="json"))
    return member


def update_location(patient_id: str, member_id: str, latitude: float, longitude: float) -> Optional[CircleMember]:
    data = db.get(_collection(patient_id), member_id)
    if data is None:
        return None
    member = CircleMember.model_validate(data)
    member.latitude = latitude
    member.longitude = longitude
    member.lastUpdated = datetime.now(timezone.utc).isoformat()
    db.put(_collection(patient_id), member_id, member.model_dump(mode="json"))
    return member


def list_members(patient_id: str) -> list[CircleMember]:
    return [CircleMember.model_validate(d) for d in db.list_all(_collection(patient_id))]


def remove_member(patient_id: str, member_id: str) -> bool:
    """Returns False if there was no such member (caller should 404)."""
    if db.get(_collection(patient_id), member_id) is None:
        return False
    db.delete(_collection(patient_id), member_id)
    return True
