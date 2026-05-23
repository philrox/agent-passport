# Agent Passport

> Cross-Venue Agent Identity Layer for prediction markets · ERC-8004 compliant · inspired by the [Agora Agents Hackathon](https://agora.thecanteenapp.com/)

## What this is

A canonical registry on Arc that bridges agent identities across multiple prediction-market venues:
- Polymarket V2 (`bytes32` builder codes)
- Hyperliquid HIP-3 / HIP-4 (builder-fee codes)
- Pump.fun (`BREAKING_FEE_RECIPIENT`)

One canonical agent ID, multiple venue-specific attributions.

## Why

Three venues invented three incompatible identity primitives within months. The [Canteen Blog](https://thecanteenapp.com/analysis/2026/05/01/unbundling-the-prediction-market-stack.html) explicitly asked for a canonical registry to bridge them. This is that registry.

## Status

🚧 Active development during Agora Agents Hackathon (May 21-25 2026).

## Reference Implementation

[VAIA Multi-Agent System](https://github.com/philrox/vaia) is the first reference implementation, registering 5 specialized agents that operate cross-venue.

## License

MIT
