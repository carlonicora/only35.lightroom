# Proposal: Only35 Lightroom Plugin

## Summary

Implement a Lightroom Classic Publish Service plugin that enables photographers to publish photos directly to Only35.

## Problem Statement

Photographers must currently:
1. Export from Lightroom to disk
2. Upload manually via web interface
3. Lose metadata continuity

## Proposed Solution

Implement `only35.lrplugin` with:
- OAuth 2.0 authentication (manual code entry fallback)
- Publish Service for collection-based uploads
- Metadata sync (stars, keywords, flags)
- Pre-signed S3 uploads via Only35 API

## Scope

### In Scope
- Plugin manifest (Info.lua)
- OAuth authentication module
- API client module
- Publish Service provider
- Metadata mapping
- Export settings configuration
- Error handling

### Out of Scope
- Server-side changes (tracked in Only35 monorepo)
- Adobe Add-ons Marketplace submission (future)

## Dependencies

- Only35 OAuth 2.0 Server (implemented)
- POST /photographs/upload-url endpoint (pending in monorepo)

## Related

- Server-side OpenSpec: /Users/carlo/Development/only35/openspec/changes/add-lightroom-plugin/
