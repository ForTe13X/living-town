"""Owned UE editor background-throttle scope with later-frame restoration proof.

No file IO, personal paths, asset mutation or realtime-override stack mutation.
Call on the same editor thread. The caller owns camera/material/selection changes
and restores them before submit_background_restore. Source-byte validation is a
required callback, so a verified viewport cannot silently qualify changed assets.
"""
from copy import deepcopy
import threading

_CDO = '/Script/UnrealEd.Default__EditorPerformanceSettings'
_PROPERTY = 'bThrottleCPUWhenNotForeground'
_VIEW_KEYS = ('world_path', 'location_cm', 'rotation_pitch_yaw_roll', 'fov',
              'lit', 'game_view', 'realtime', 'client_identity_diagnostic_only',
              'viewport_identity_diagnostic_only')

def _need(value, message):
    if not value:
        raise ValueError(message)

def _context(unreal):
    return {'frame': int(unreal.SystemLibrary.get_frame_count()),
            'OS_thread': threading.get_native_id(),
            'Python_thread': threading.get_ident()}

def _same_thread(left, right):
    _need(all(left[k] == right[k] for k in ('OS_thread', 'Python_thread')),
          'Background scope must remain on its original editor thread')

def begin_background_scope(unreal, read_current):
    """Capture actual current-client state, then disable owned background throttle.

    This does not force a non-realtime base viewport to become realtime. The
    caller must still require actual realtime readiness before taking pictures.
    The returned token contains a live CDO and is not a serialized receipt.
    """
    before = deepcopy(read_current())
    _need(all(k in before for k in _VIEW_KEYS), 'Complete native viewport readback required')
    cdo = unreal.find_object(None, _CDO)
    _need(cdo is not None, 'Editor performance CDO absent')
    throttle = bool(cdo.get_editor_property(_PROPERTY))
    token = {'phase': 'ACTIVE', 'before': before, 'cdo': cdo,
             'original_throttle': throttle, 'begin': _context(unreal)}
    cdo.set_editor_property(_PROPERTY, False)
    _need(cdo.get_editor_property(_PROPERTY) is False, 'Background throttle change refused')
    return token

def submit_background_restore(unreal, token):
    """Restore the CDO after caller-owned camera and scene state are restored."""
    _need(token['phase'] == 'ACTIVE', 'One active background scope required')
    now = _context(unreal)
    _same_thread(now, token['begin'])
    token['cdo'].set_editor_property(_PROPERTY, token['original_throttle'])
    _need(token['cdo'].get_editor_property(_PROPERTY) == token['original_throttle'],
          'Original background throttle not restored')
    token['submitted'] = now
    token['phase'] = 'RESTORE_SUBMITTED'
    return {'status': 'WAIT_LATER_NATIVE_BACKGROUND_TICK', 'submitted': now}

def verify_background_restore(unreal, token, read_current, verify_source_bytes):
    """Poll without heavy work; accept only exact state after two native frames."""
    _need(token['phase'] == 'RESTORE_SUBMITTED', 'Restore must be submitted once before verification')
    now = _context(unreal)
    submitted = token['submitted']
    _same_thread(now, submitted)
    if now['frame'] < submitted['frame'] + 2:
        return {'status': 'PENDING_LATER_NATIVE_BACKGROUND_TICK',
                'submitted': submitted, 'observed': now}
    actual = deepcopy(read_current())
    _need(all(actual[k] == token['before'][k] for k in _VIEW_KEYS),
          'Original viewport including effective realtime not restored')
    _need(token['cdo'].get_editor_property(_PROPERTY) == token['original_throttle'],
          'Original background CDO differs')
    _need(verify_source_bytes() is not False, 'Source-byte validation refused')
    token['phase'] = 'RESTORED'
    return {'status': 'RESTORED_EXACT_AFTER_NATIVE_BACKGROUND_TICK',
            'submitted': submitted, 'observed': now, 'viewport': actual,
            'source_bytes_verified': True}
