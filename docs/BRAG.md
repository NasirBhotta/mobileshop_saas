# 🚀 MobileShop SaaS — Engineering Brag Sheet

**Author:** Nasir Bhutta  
**Product:** MobileShop SaaS  
**Stack:** Flutter 3.x, Dart, Riverpod, Drift (SQLite), Supabase (PostgreSQL), ESC/POS Thermal Printing  
**Last Updated:** October 2026  

---

## Executive Summary
Single-handedly architected, developed, tested, and hardened an enterprise-scale multi-branch SaaS platform for mobile retail and repair centers. Built an offline-first architecture with native thermal hardware drivers, double-entry financial ledgers, repair lifecycle workflows, and transactional security RPCs.

---

## 📈 Impact by the Numbers

- **90,076+ Lines of Production Dart Code** across 16 core business domains.
- **13,646+ Lines of Tests** in **153 dedicated test suites**.
- **223 Git Commits** on `main` maintaining continuous verification.
- **Zero-Data-Loss Offline Architecture** powered by Drift SQLite and Supabase.
- **Sub-100ms POS Checkout Latency** on local SQLite before asynchronous cloud sync.

---

## 🛠️ Major Projects & Feature Accomplishments

### 1. Enterprise Point of Sale (POS) & Checkout Engine
- **High-Velocity Barcode & IMEI Scanning:** Designed product lookup that handles accessories, barcoded stock, and IMEI-serialized phones seamlessly (`lib/features/pos/presentation/providers/pos_provider.dart`, `lib/features/pos/presentation/widgets/product_search_panel.dart`).
- **Hardware-Level ESC/POS Thermal Printing:**
  - Built raw byte-level network TCP thermal printing (`lib/features/printing/escpos/escpos_tcp_printer.dart`).
  - Implemented Windows desktop C++ integration (`windows/cmake/thermal_printing.cmake`) for zero-delay USB/virtual COM receipts.
  - Engineered dynamic receipt layout engine (`lib/core/printing/receipt_layout.dart`) and barcode sticker generator (`lib/core/printing/sticker_layout.dart`).
- **Sale Lifecycle Management:** Integrated split payments (Cash, Card, Bank Transfer, Customer Credit) and instant refunds/returns with automated stock restock.

### 2. Offline-First Drift Synchronization Engine
- **Local-First Reliability:** Implemented full offline operation using Drift (SQLite) as the source of truth for POS and inventory (`lib/core/local/local_store.dart`).
- **Resilient Sync Engine:** Built `inventory_sync_engine.dart` and `inventory_refresh_coordinator.dart` to handle bidirectional updates, conflict resolution, and background sync queues.
- **Cache Snapshotting:** Designed snapshot caching mechanisms (`test/features/pos/sale_cache_snapshot_test.dart`) to eliminate UI stutter during large catalog queries.

### 3. Comprehensive Workshop & Repair Management
- **End-to-End Ticket Lifecycle:** Track devices from Intake -> Diagnostics -> Parts Estimation -> Customer Approval -> Technician Repair -> Quality Control -> Handover (`lib/features/repairs/presentation/screens/repairs_list_screen.dart`, `lib/features/repairs/presentation/screens/repair_form_screen.dart`).
- **Pre-Repair Inspection Media:** Photo capture and storage for device pre-existing condition verification (`test/features/repairs/repair_ticket_photos_test.dart`).
- **Automated Accounting Effects:** Created `RepairAccountingEffect` to automatically record technician labor costs, parts inventory consumption, and gross profit into the general ledger.

### 4. Customer Buy-In (Device Trade-In / Second-Hand Intake)
- **Legal & Anti-Fraud Compliance:** Developed verification flows requiring customer CNIC/ID, phone provenance records, IMEI checks, and signed purchase agreements.
- **Instant Inventory Ingestion:** Automatically injects tested, graded devices into inventory at acquisition cost upon contract completion.

### 5. Multi-Branch Operations & SaaS Tenant Isolation
- **Branch Management:** Native support for multi-location inventory transfers, inter-branch requisition, and branch-isolated sales reporting.
- **Granular RBAC:** Role-based permission catalog segregating Cashier, Technician, Branch Manager, and Super Admin privileges.

---

## 🔒 Security Hardening & Infrastructure Milestones

### The SEC-17 Direct-Write Mitigation Initiative
- **Vulnerability Elimination:** Eliminated client-direct table mutations on critical business tables (`sales`, `inventory`, `customer_buyins`) in favor of atomic, strictly audited PostgreSQL Stored Procedures.
- **Transactional Stored Procedures:** Implemented PostgreSQL RPCs:
  - `secure_customer_buyin_rpc`
  - `secure_inventory_adjustment_rpc`
  - `secure_product_sync_rpc`
  - `secure_pos_return_restore_rpc`
- **Automated Staging Runbooks:** Authored scripts and runbooks (`scripts/clone_public_schema_to_staging.ps1`, `docs/production_security_plan.md`) to test security policies and permission enforcement in isolated sandbox environments prior to production rollout.

---

## 🧪 Testing & Quality Assurance Rigor

- **153 Test Suites Covering:**
  - **POS Core & Layout:** `test/features/pos/receipt_service_test.dart`, `test/features/pos/receipt_layout_regression_test.dart`
  - **Sync Safety & Queue Invariants:** `test/features/inventory/inventory_sync_queue_safety_test.dart`, `test/features/inventory/inventory_refresh_integration_test.dart`
  - **Hardware Thermal Output:** `test/features/printing/escpos_receipt_test.dart`
  - **Financial & Stock Reporting:** `test/features/reports/inventory_low_stock_report_test.dart`

---

## 🧭 What's Next
1. **Web Dashboard Expansion:** Complete responsive web endpoints and reporting portals (`docs/security_direct_write_transition.md`).
2. **Customer Portal / WhatsApp Notifications:** Automated SMS/WhatsApp repair status updates and digital receipt sharing.
3. **Automated Supplier Purchase Orders:** Predictive low-stock triggers with automated purchase order generation.
