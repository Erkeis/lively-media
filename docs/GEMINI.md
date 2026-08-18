# DOCUMENTATION DIRECTORY RULES (`docs/GEMINI.md`)

## 1. PURPOSE & SSOT
- The `docs/` directory is the single source of truth (SSOT) for system architecture, research benchmarks, networking specs, and server setup.
- All documents must be kept in sync with actual code implementations.

## 2. FORMAT & STRUCTURE
- Use GitHub Flavored Markdown (GFM).
- Use Mermaid diagrams for architecture flows, sequence diagrams, and class relationships.
- Use explicit section headings: `# Title`, `## Overview`, `## Technical Details`, `## Verification`.
- Avoid vague placeholders; include concrete configurations, endpoints, and data schemas.

## 3. CHANGE MANAGEMENT
- When introducing or altering APIs, playback protocols, or server endpoints, update the corresponding markdown file in this directory in the same commit.
