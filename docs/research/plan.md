# AAC Intervention: Selection and Usage of Communication Devices — Research Plan

**Status:** Awaiting creator review and approval
**Researcher:** [Name]
**Last updated:** April 21, 2026

---

## Purpose

Blaster has been built without direct input from its intended users. Before investing further in features like the scene editor, child profiles, and tile redesign, we need to understand how the professionals who recommend, configure, and use AAC tools with children actually work — their clinical and behavioral workflows, frustrations with existing tools, and what would make Blaster genuinely useful in practice.

AAC is used by a wide range of people across varying degrees of speech, language, and communication difficulty — from children with autism or cerebral palsy to adults with acquired conditions like ALS or stroke. **This study focuses on two professional cohorts who work with children: Speech-Language Pathologists (SLPs) and Board-Certified Behavior Analysts (BCBAs) / behavioral therapists.** These groups often share patients but approach AAC with different theoretical frameworks and goals — a tension that directly affects how tools like Blaster should be designed.

We are explicitly not interviewing family members, educators, or personal care assistants in this round. The assumption driving that scope decision — that SLPs are the primary AAC recommending authority — is itself a hypothesis to be tested and refined through these interviews.

This study is **generative**: we are not testing Blaster's current design. We are learning about the problem space so that every subsequent design decision is grounded in real clinical experience.

---

## Research Questions

**Across both cohorts:**
1. How do professionals in each discipline evaluate, recommend, and set up AAC tools for children — and what does that process actually look like in practice?
2. What are the biggest frustrations each group has with current AAC tools (device-based, app-based, or paper-based)?
3. What factors beyond clinical or behavioral judgment influence which AAC tool a child ends up using (insurance, funding, school systems, team dynamics)?
4. What would an ideal AAC tool look like from each discipline's perspective?

**SLP-specific:**
5. How do SLPs approach vocabulary selection and customization, and how does that evolve over time with a child?
6. How do SLPs collaborate with (or differ from) behavioral therapists on AAC goals and implementation?

**Behavioral therapist-specific:**
7. How do behavioral therapists use AAC within the context of behavior intervention plans — and how does that differ from a language development framework?
8. Where do behavioral goals and communication goals align, and where do they create tension or conflict?

**Cross-cutting:**
9. How do the two disciplines coordinate (or fail to coordinate) when both are working with the same child?
10. Who ultimately drives AAC adoption and daily use — and how do professionals from each discipline perceive their own influence relative to the other?

---

## Methodology

- **Format:** Semi-structured remote interviews via video call (Zoom or Google Meet)
- **Duration:** 30 minutes per session
- **Sessions:** 6–10 participants across two cohorts (3–5 SLPs, 3–5 behavioral therapists)
- **Recording:** Audio + video with participant consent (NDA required — see `nda.md`)

---

## Participant Criteria

### Cohort A — Speech-Language Pathologists (3–5 participants)

**Must haves:**
- Licensed Speech-Language Pathologist (SLP / CCC-SLP)
- Currently works with children (ages 3–12) who are non-verbal or minimally verbal
- Has recommended, configured, or supported AAC use with at least one child patient

**Nice to haves:**
- Mix of practice settings (school-based, clinic-based, private practice, early intervention)
- Mix of experience levels (early-career vs. 5+ years with AAC)
- Experience across multiple AAC tools (Proloquo2Go, TouchChat, LAMP, PECS, etc.)

---

### Cohort B — Behavioral Therapists (3–5 participants)

**Must haves:**
- Board-Certified Behavior Analyst (BCBA) or equivalent behavioral therapist credential
- Currently works with children (ages 3–12) who are non-verbal or minimally verbal
- Has used or incorporated AAC within a behavioral intervention plan

**Nice to haves:**
- Mix of practice settings (ABA clinic, school-based, home-based, early intervention)
- Mix of experience levels (early-career vs. 5+ years with non-verbal clients)
- Experience collaborating (or conflicting) with SLPs on shared cases

---

**Out of scope for this study:**
- Family members, parents, or guardians (future study)
- Educators and special education teachers (future study)
- Personal care assistants (PCAs) (future study)
- Professionals who work exclusively with adults

---

## Assumptions & Risks

### Assumptions

| Assumption | Rationale |
|---|---|
| SLPs are a primary driver of AAC tool selection | SLPs typically conduct AAC evaluations, make formal recommendations, and lead initial device setup — making them a high-leverage entry point for understanding tool adoption. This assumption is treated as a hypothesis to be tested. |
| Behavioral therapists have meaningfully different AAC goals than SLPs | Research suggests SLPs prioritize language development and spontaneous communication, while BCBAs may prioritize functional communication and behavior reduction — a tension worth surfacing directly. |
| Insights from both cohorts will inform Blaster's design | Both disciplines configure vocabulary and support daily AAC use; their shared and divergent pain points map directly to Blaster's planned features |
| 6–10 participants across two cohorts is sufficient for generative research | At this stage we are looking for themes and patterns, not statistical significance |

### Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| **AAC selection is system-driven, not profession-driven alone.** Insurance coverage, school district contracts, and funding sources heavily influence which device a child receives — individual recommendations do not always win. | High | Explicitly probe for the full decision ecosystem in interviews; treat "who recommends" as an open question |
| **SLPs and behavioral therapists may have conflicting views that are hard to reconcile into unified design guidance.** | High | Treat divergence as a finding, not a problem; insight report should surface the tension explicitly and let design decisions reflect the tradeoffs |
| **Professional perspective may not represent family or child experience.** Caregivers and children are the daily users of AAC; these cohorts reflect clinical and behavioral needs, not lived use. | High | Acknowledge this gap explicitly in the insight report; plan a follow-on caregiver/family study |
| **Recruiting professionals may be slow.** SLPs and BCBAs are smaller, harder-to-reach populations without the open community forums that caregiver groups have. | Medium | Leverage ASHA, ABAI, and discipline-specific Facebook groups; university clinic contacts; build in extra recruiting lead time |
| **Participants may have privacy concerns about discussing patient cases.** | Medium | Frame interviews around general workflow and clinical experience, not specific patients; NDA and de-identification protocols in place |
| **Study scope is narrow.** Excluding families, educators, and PCAs means we may miss significant drivers of AAC use and abandonment. | Medium | Note explicitly as a limitation; scope future studies to fill these gaps |

---

## Outputs

| Deliverable | Description | Due |
|---|---|---|
| Interview recordings | Raw session recordings (stored securely, access-controlled) | May 22 |
| Session notes | Anonymized notes per participant | May 22 |
| Affinity map | Synthesized themes across sessions | May 30 |
| Insight report | Key findings + design recommendations | Jun 5 |

The insight report will include specific recommendations for:
- Tile vocabulary and visual design
- Scene/page editor for caregivers
- Child profile setup
- Admin panel improvements

---

## Milestone Timeline

| Milestone | Owner | Due |
|---|---|---|
| Creator reviews & approves this plan | markl | Apr 23 |
| NDA reviewed (legal sanity check recommended) | markl | Apr 23 |
| Recruiting materials finalized | Researcher | Apr 25 |
| Outreach begins | Researcher | Apr 28 |
| Participants screened & scheduled (6–10 confirmed across both cohorts) | Researcher | May 9 |
| Interviews conducted | Researcher | May 10–22 |
| Synthesis complete | Researcher | May 30 |
| Insight report delivered | Researcher | Jun 5 |

---

## Creator Action Required

Please review this plan and confirm the following before April 23:

- [ ] Research questions are aligned with your product priorities
- [ ] Participant criteria make sense for the intended audience
- [ ] You are comfortable with remote video interviews as the method
- [ ] NDA template reviewed (see `nda.md`) — legal review recommended before use
- [ ] You are comfortable with beta access as the participant incentive (no monetary compensation)

Leave comments inline or reach out directly to the researcher.
