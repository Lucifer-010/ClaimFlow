# ClaimFlow

> **Blockchain-Powered Insurance Claims Management, Soroban Smart Contract Approval & Payout Authorization on Stellar**

[![Smart Contract Tests](https://img.shields.io/badge/Soroban%20Contract%20Tests-16%2F16%20Passed-brightgreen)](file:///home/lucifer/Desktop/ClaimFlow/contracts)
[![Backend Tests](https://img.shields.io/badge/Django%20Unit%20Tests-24%2F24%20Passed-brightgreen)](file:///home/lucifer/Desktop/ClaimFlow/backend)
[![OpenAPI 3.0](https://img.shields.io/badge/OpenAPI%203.0-Swagger%20%26%20ReDoc-blue)](file:///home/lucifer/Desktop/ClaimFlow/backend/openapi-schema.yml)
[![Docker](https://img.shields.io/badge/Docker-Postgres%20%7C%20Redis%20%7C%20Celery-blueviolet)](file:///home/lucifer/Desktop/ClaimFlow/docker-compose.yml)

---

## 1. Project Overview

**ClaimFlow** is an enterprise-grade insurance claims management platform built on Stellar that enables claimants to submit claims, authorized reviewers to assess and approve/reject claims, and administrators to track verifiable payout authorizations and transaction settlement.

The platform eliminates fragmented claim records, inconsistent approval procedures, and opaque payout timelines by integrating **Stellar Soroban smart contracts** directly with a scalable **Django REST Framework + PostgreSQL + Redis/Celery** backend.

### Critical Scope Distinction: Approval vs. Authorization vs. Settlement

ClaimFlow enforces strict architectural boundaries across the payout lifecycle:
1. **Claim Approved**: Authorized reviewer validates the incident and sets the approved compensation amount. *No funds are transferred.*
2. **Payout Authorized**: Soroban smart contract immutably records authorization for an amount $\le$ approved amount. *Prevents double-authorization. No funds are transferred.*
3. **Settled**: Actual Stellar Testnet transaction transfer is executed and confirmed with a verifiable transaction hash.

| Lifecycle Stage | Meaning | On-Chain State | Funds Transferred? |
| :--- | :--- | :--- | :---: |
| **Submitted** | Claim created with policy reference & evidence | `Submitted` | ❌ No |
| **Under Review** | Reviewer assigned & assessing claim | `UnderReview` | ❌ No |
| **Approved** | Reviewer validates claim & sets approved amount | `Approved` | ❌ No |
| **Rejected** | Reviewer rejects claim with comments | `Rejected` | ❌ No |
| **Payout Authorized** | Payout authorization recorded on Soroban | `PayoutAuthorized` | ❌ No |
| **Settled** | Stellar payment transaction confirmed | `Settled` | ✅ **Yes** |

---

## 2. Architecture & Tech Stack

```
                        +---------------------------------------+
                        |         ClaimFlow Client UI           |
                        | (Claimant / Reviewer / Admin Portals) |
                        +-------------------+-------------------+
                                            |
                                            | REST / JWT
                                            v
+-----------------------------------------------------------------------------------+
|                            Django Backend (Gunicorn)                              |
|                                                                                   |
|  +--------------------+  +--------------------+  +-----------------------------+  |
|  | Authentication App |  |    Policies App    |  |         Claims App          |  |
|  | - JWT auth         |  | - Coverage limits  |  | - State machine & workflow  |  |
|  | - Role permissions |  | - Deductibles      |  | - Supporting evidence       |  |
|  |   (Claimant/       |  | - Active policies  |  | - Review decisions          |  |
|  |    Reviewer/Admin) |  |                    |  | - Payout authorization      |  |
|  +--------------------+  +--------------------+  +-----------------------------+  |
|                                         |                                         |
|  +--------------------------------------+  +-----------------------------------+  |
|  |           Blockchain App             |  |         OpenAPI / Swagger         |  |
|  | - Soroban RPC Client / Web3 Service  |  | - drf-spectacular schema (3.0)    |  |
|  | - Transaction monitoring & explorer  |  | - Swagger UI at /api/docs/        |  |
|  | - Ledger verification                |  | - ReDoc at /api/redoc/            |  |
|  +--------------------------------------+  +-----------------------------------+  |
+--------------------------+------------------------------------+-------------------+
                           |                                    |
                           v                                    v
            +------------------------------+     +-------------------------------+
            |    PostgreSQL Database       |     |     Redis & Celery Workers    |
            | - Strict Foreign Keys        |     | - Async contract interactions |
            | - Immutable Audit Timeline   |     | - Periodic transaction sync   |
            | - Transaction Records        |     | - Scheduled reconciliation    |
            +------------------------------+     +-------------------------------+
                                                        |
                                                        v
                                         +------------------------------+
                                         |    Stellar Soroban Network   |
                                         | (Rust Smart Contract Wasm)   |
                                         | - Unique claim registration  |
                                         | - Role-based access control  |
                                         | - State transition checks    |
                                         | - Duplicate payout prevention|
                                         | - Event emission             |
                                         +------------------------------+
```

### Technology Matrix
- **Smart Contract**: Rust, `soroban-sdk` v28, compiled to `wasm32v1-none`
- **Backend Framework**: Python 3.12 / 3.13, Django 5.1, Django REST Framework 3.15
- **Authentication**: `djangorestframework-simplejwt` (Role-Based Access Control)
- **API Documentation**: `drf-spectacular` (OpenAPI 3.0, Swagger UI, ReDoc)
- **Database**: PostgreSQL 16 (persistent relational records and indexing)
- **Task Queue & Cache**: Redis 7 Alpine, Celery 5.4, Celery Beat
- **Blockchain Integration**: `stellar-sdk` Python + Soroban RPC + Rust Soroban Contract

---

## 3. Soroban Smart Contract (`contracts/claimflow`)

The Soroban smart contract enforces immutable claim state transitions, reviewer authorization, and duplicate payout prevention directly on the Stellar ledger.

### Contract Functions (`lib.rs`)

| Function | Access Control | Description |
| :--- | :--- | :--- |
| `initialize(admin)` | Admin | Initializes contract with admin address and sets default reviewer |
| `add_reviewer(caller, reviewer)` | Admin | Grants reviewer privileges to a Stellar address |
| `remove_reviewer(caller, reviewer)` | Admin | Revokes reviewer privileges |
| `is_reviewer(account)` | Public | Checks if an address has reviewer rights |
| `get_admin()` | Public | Returns the contract administrator |
| `register_claim(claimant, claim_id, policy_id, requested_amount)` | Claimant | Registers unique claim reference; validates requested amount $> 0$ |
| `move_to_review(reviewer, claim_id)` | Reviewer | Transitions status from `Submitted` to `UnderReview` |
| `approve_claim(reviewer, claim_id, approved_amount, notes)` | Reviewer | Transitions status from `UnderReview` to `Approved` with approved amount |
| `reject_claim(reviewer, claim_id, notes)` | Reviewer | Transitions status from `UnderReview` to `Rejected` with comments |
| `authorize_payout(caller, claim_id, payout_amount)` | Reviewer/Admin | Authorizes payout for `Approved` claim; validates payout $\le$ approved amount; prevents duplicate authorization |
| `settle_claim(caller, claim_id, settlement_ref)` | Reviewer/Admin | Transitions `PayoutAuthorized` claim to `Settled` with external settlement transaction hash |
| `get_claim(claim_id)` | Public | Reads verified on-chain claim record |
| `claim_exists(claim_id)` | Public | Checks whether a claim reference is registered |
| `get_total_claims()` | Public | Returns total count of registered claims |
| `get_claim_by_index(index)` | Public | Fetches claim reference by index |

### Contract Verification Suite (16 Scenarios)

All 16 test scenarios specified in `project.txt` are implemented and verified in `contracts/contracts/claimflow/src/test.rs`:

```bash
cd contracts
cargo test
```

**Results:**
```text
running 16 tests
test test::test_scenario_01_submit_valid_claim ... ok
test test::test_scenario_02_submit_incomplete_claim_validation_error ... ok
test test::test_scenario_03_generate_unique_claim_reference ... ok
test test::test_scenario_04_move_claim_to_review ... ok
test test::test_scenario_05_authorized_reviewer_approves_claim ... ok
test test::test_scenario_06_authorized_reviewer_rejects_claim ... ok
test test::test_scenario_07_unauthorized_reviewer_attempts_approval ... ok
test test::test_scenario_08_approve_already_rejected_claim_fails ... ok
test test::test_scenario_09_authorize_payout_for_approved_claim ... ok
test test::test_scenario_10_authorize_payout_for_rejected_claim_fails ... ok
test test::test_scenario_11_duplicate_payout_authorization_fails ... ok
test test::test_scenario_12_authorization_exceeds_approved_amount_fails ... ok
test test::test_scenario_13_unauthorized_claim_state_change ... ok
test test::test_scenario_14_failed_contract_transaction_state_remains_consistent ... ok
test test::test_scenario_15_verify_authorization_history ... ok
test test::test_scenario_16_monitor_optional_actual_payment_settlement_tracked_separately ... ok

test result: ok. 16 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out; finished in 0.03s
```

### Compiling Contract to WASM
```bash
cd contracts
stellar contract build
# Or: cargo build --target wasm32v1-none --release
```
Artifact generated: `target/wasm32v1-none/release/claimflow.wasm` (10,558 bytes optimized).

---

## 4. Backend REST API Reference

The backend provides full Swagger UI (`/api/docs/`) and ReDoc (`/api/redoc/`) documentation.

### Authentication Endpoints
- `POST /api/v1/auth/register/` - Register account with role (`CLAIMANT`, `REVIEWER`, `ADMIN`) and Stellar wallet
- `POST /api/v1/auth/login/` - Authenticate with JWT token pair (`access`, `refresh`)
- `POST /api/v1/auth/token/refresh/` - Refresh JWT access token
- `GET /api/v1/auth/me/` - Get current authenticated user profile

### Policy Endpoints
- `GET /api/v1/policies/` - List policies (Claimants see own; Reviewers/Admins see all)
- `POST /api/v1/policies/` - Create policy (Admins/Reviewers)
- `GET /api/v1/policies/{id}/` - Retrieve policy details

### Claim Lifecycle Endpoints
- `GET /api/v1/claims/` - List claims (filterable by status, category, date, policy)
- `POST /api/v1/claims/` - Submit a new insurance claim with evidence
- `GET /api/v1/claims/{id}/` - Detailed claim record
- `POST /api/v1/claims/{id}/review/` - Move claim to `UNDER_REVIEW` (Reviewer/Admin)
- `POST /api/v1/claims/{id}/approve/` - Approve claim with approved amount and comments
- `POST /api/v1/claims/{id}/reject/` - Reject claim with comments
- `POST /api/v1/claims/{id}/authorize_payout/` - Authorize payout on Soroban ($\le$ approved amount)
- `POST /api/v1/claims/{id}/settle/` - Settle claim with confirmed Stellar payment tx hash
- `GET /api/v1/claims/{id}/timeline/` - Chronological audit timeline of claim history
- `POST /api/v1/claims/{id}/evidence/` - Attach supporting evidence documents

### Payout Dashboard Endpoints
- `GET /api/v1/payouts/` - List authorized payouts with statuses and explorer links
- `GET /api/v1/payouts/{id}/` - Retrieve specific payout record
- `GET /api/v1/payouts/pending-claims/` - List approved claims awaiting payout authorization

### Blockchain Monitoring Endpoints
- `GET /api/v1/blockchain/contract-info/` - Get deployed Soroban contract address, RPC URL, and network status
- `GET /api/v1/blockchain/transactions/` - List recorded transactions with status and explorer links
- `GET /api/v1/blockchain/transactions/{tx_hash}/` - Verify transaction by hash
- `GET /api/v1/blockchain/claims/{claim_reference}/` - Query verified claim state directly from Soroban

### Dashboard Metrics Endpoint
- `GET /api/v1/claims/dashboard/metrics/` - Aggregated platform statistics (counts by status, requested vs. authorized vs. settled volumes)

---

## 5. Quick Start with Docker

### Prerequisites
- Docker Engine $\ge$ 24.0
- Docker Compose $\ge$ 2.20

### Start the Platform
```bash
# 1. Clone repository
git clone https://github.com/lucifer/ClaimFlow.git
cd ClaimFlow

# 2. Configure environment
cp .env.example .env

# 3. Build and launch services
docker compose up --build -d
```

Services started:
- `claimflow_web`: Django API & Gunicorn on `http://localhost:8000`
- `claimflow_db`: PostgreSQL 16 on `localhost:5432`
- `claimflow_redis`: Redis 7 on `localhost:6379`
- `claimflow_celery_worker`: Celery worker for async contract sync
- `claimflow_celery_beat`: Celery beat for scheduled reconciliation

### Interactive API Documentation
- Swagger UI: [http://localhost:8000/api/docs/](http://localhost:8000/api/docs/)
- ReDoc: [http://localhost:8000/api/redoc/](http://localhost:8000/api/redoc/)
- Raw OpenAPI 3.0 Schema: [http://localhost:8000/api/schema/](http://localhost:8000/api/schema/)

---

## 6. Local Development Setup (Without Docker)

### 1. Python Virtual Environment
```bash
cd backend
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt
```

### 2. Apply Database Migrations
```bash
python manage.py migrate
```

### 3. Run Backend Unit & Integration Tests
```bash
python manage.py test apps.authentication apps.policies apps.blockchain apps.claims
```
**Results:**
```text
Ran 24 tests in 8.323s
OK
```

### 4. Run Celery Worker & Local Server
```bash
# Terminal 1: Celery Worker
celery -A claimflow_core worker -l info

# Terminal 2: Django Dev Server
python manage.py runserver 0.0.0.0:8000
```

---

## 7. Automated Testing Summary

| Test Suite | Location | Tests Executed | Passed | Status |
| :--- | :--- | :---: | :---: | :---: |
| **Soroban Smart Contract** | `contracts/contracts/claimflow/src/test.rs` | 16 | 16 | ✅ Passed |
| **Authentication & RBAC** | `backend/apps/authentication/tests.py` | 4 | 4 | ✅ Passed |
| **Policy Management** | `backend/apps/policies/tests.py` | 3 | 3 | ✅ Passed |
| **Blockchain Integration** | `backend/apps/blockchain/tests.py` | 3 | 3 | ✅ Passed |
| **Claim Lifecycle & Payouts** | `backend/apps/claims/tests.py` | 14 | 14 | ✅ Passed |
| **Total** | | **40** | **40** | ✅ **100% Passed** |

---

## 8. License

ClaimFlow is open-source software licensed under the MIT License.
