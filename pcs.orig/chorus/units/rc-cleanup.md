---
objective: Clean up inconsistencies, dead code, and interface mismatches before RC
status: complete
---

RC cleanup. Fix all issues identified in the full codebase review that would cause runtime failures, confusion, or maintenance burden before going live in the SG data center.

## Completion Criteria

- Host STI subclasses all conform to the base class interface (same method signatures)
- No references to nonexistent constants, removed parameters, or stale method signatures
- Dead code removed (orphaned files, legacy templates, unreachable code paths)
- Dnsmasq adapter calculates netmask from subnet instead of hardcoding /24
- Profile model's `[]` method removed or justified with a comment
- All specs pass
- No regressions in existing functionality
