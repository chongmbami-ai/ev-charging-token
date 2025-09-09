# EV Charging Token — Development PR

This PR adds the core smart contracts and initial project scaffolding for the EV Charging Token system.

## Summary

- Add a fungible token (EVT) for pay-per-use EV charging
- Implement usage-based billing contract with metering and cost calculation
- Implement access control contract for stations and users
- Basic tests and configuration included

## Contracts

- token.clar — SIP-010-like fungible token for payments (development mode)
- billing.clar — session management, pricing, and payments (development mode)
- access.clar — station registration, permissions, and access control

## Notes

- External token transfers are stubbed for development (no cross-contract calls)
- Trait implementation commented for local testing
- All contracts pass `clarinet check`
- Minimal tests run and pass with `npm test`

## Testing

```bash
clarinet check
npm install
npm test
```

## Next Steps

- Wire token transfers to actual SIP-010 contract in production
- Expand test coverage and integrate station hardware events
- Add station operator withdrawal functions and full accounting

