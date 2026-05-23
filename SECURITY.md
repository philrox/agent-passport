# Security Policy

## Supported Versions

This project is in active early development. Only the `main` branch is supported. The deployed contracts on Arc Testnet are versioned per `deployments/arc-testnet.json` and are **not intended for mainnet use until audited**.

## Reporting a Vulnerability

**Do not open public GitHub issues for security vulnerabilities — including smart-contract vulnerabilities.**

Please report security issues privately by emailing:

**philipp.sparoutz@gmail.com**

Include:

- Description of the vulnerability
- Steps to reproduce (transaction hashes, contract address if applicable)
- Potential impact (funds at risk, integrity, availability)
- (Optional) Suggested fix or proof-of-concept

We will acknowledge receipt within 72 hours and aim to provide a fix within 7 days for critical issues. For coordinated disclosure of high-severity findings, we will work with you on a disclosure timeline.

## Scope

In-scope security concerns include:

- Smart contract vulnerabilities (reentrancy, access control, storage collisions, gas griefing, integer issues, signature replay, etc.)
- SDK signing or key-handling defects
- Deployment script issues that could leak funds or compromise contract ownership
- Cross-venue adapter logic that could misattribute fees or builder codes

Out of scope:

- Issues in third-party dependencies (please report upstream)
- Issues requiring physical access or compromised user devices

## Smart Contract Disclaimer

The contracts in this repository are **unaudited** and intended for testnet use during the hackathon period. Do not use them with real funds without an independent security audit. Use of these contracts on mainnet is at your own risk.

## Hall of Fame

Reporters of valid vulnerabilities will be credited (with consent) in release notes and a future `SECURITY-CONTRIBUTORS.md` file.
