# ============================================================
# FreelancePilot AI — AI Service
# apps/api/app/services/ai_service.py
# ============================================================

from __future__ import annotations
import json, re
from typing import Literal
from openai import AsyncOpenAI
from anthropic import AsyncAnthropic

from app.config import settings
from app.core.database import AsyncSession
from app.repositories.proposal_repository import ProposalRepository
from app.repositories.job_repository import JobRepository


# ── Model Router ─────────────────────────────────────────────

ModelType = Literal["openai", "claude"]

class ModelRouter:
    """Route requests to OpenAI or Claude based on task type and cost."""

    def __init__(self):
        self.openai  = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)
        self.claude  = AsyncAnthropic(api_key=settings.ANTHROPIC_API_KEY)

    async def complete(
        self,
        prompt: str,
        system: str = "",
        model: ModelType = "openai",
        temperature: float = 0.7,
        max_tokens: int = 1500,
        json_mode: bool = False,
    ) -> tuple[str, int, int]:
        """Returns (text, input_tokens, output_tokens)."""
        if model == "openai":
            return await self._openai_complete(prompt, system, temperature, max_tokens, json_mode)
        return await self._claude_complete(prompt, system, temperature, max_tokens)

    async def _openai_complete(self, prompt, system, temperature, max_tokens, json_mode):
        kwargs = dict(
            model="gpt-4o",
            messages=[
                {"role": "system", "content": system or "You are a helpful assistant."},
                {"role": "user", "content": prompt},
            ],
            temperature=temperature,
            max_tokens=max_tokens,
        )
        if json_mode:
            kwargs["response_format"] = {"type": "json_object"}
        resp = await self.openai.chat.completions.create(**kwargs)
        text = resp.choices[0].message.content or ""
        return text, resp.usage.prompt_tokens, resp.usage.completion_tokens

    async def _claude_complete(self, prompt, system, temperature, max_tokens):
        resp = await self.claude.messages.create(
            model="claude-sonnet-4-20250514",
            max_tokens=max_tokens,
            system=system,
            messages=[{"role": "user", "content": prompt}],
            temperature=temperature,
        )
        text = resp.content[0].text if resp.content else ""
        return text, resp.usage.input_tokens, resp.usage.output_tokens


# ── Embedding Service ─────────────────────────────────────────

class EmbeddingService:
    def __init__(self):
        self.client = AsyncOpenAI(api_key=settings.OPENAI_API_KEY)

    async def embed(self, text: str) -> list[float]:
        resp = await self.client.embeddings.create(
            model="text-embedding-3-small",
            input=text[:8000],  # safe truncation
        )
        return resp.data[0].embedding


# ── Prompt Templates ──────────────────────────────────────────

PROPOSAL_SYSTEM = """You are an elite freelance proposal writer with a 10-year track record.
You write proposals that:
- Sound 100% human, never robotic or AI-generated
- Reference the client's specific pain points
- Demonstrate genuine understanding of the project
- Include relevant personal experience
- Have a strong, natural CTA
- Are concise but impactful
Never use phrases like "I hope this finds you well", "Please don't hesitate", or "looking forward to hearing from you".
Output ONLY the proposal text, nothing else."""

JOB_ANALYSIS_SYSTEM = """You are an expert freelance strategist. Analyze job postings and return JSON only.
Never include markdown fences or explanatory text outside the JSON."""

FOLLOWUP_SYSTEM = """You are a professional freelance consultant writing a follow-up message.
Sound natural and human. Do not be pushy or desperate. Keep it short (2-3 sentences max)."""




# Arabic AI Support
SUPPORTED_LANGUAGES = ["en", "ar"]
ARABIC_SYSTEM_PROMPT = """أنت مساعد فريلانس عربي احترافي متخصص في ERP والمحاسبة وExcel وPower BI. اكتب عروض بشرية احترافية ومقنعة."""

# ── Main AI Service ───────────────────────────────────────────

class AIService:

    def __init__(self, db: AsyncSession):
        self.db       = db
        self.router   = ModelRouter()
        self.embedder = EmbeddingService()
        self.job_repo = JobRepository(db)
        self.prop_repo = ProposalRepository(db)

    async def analyze_job(self, job_description: str, profile: dict) -> dict:
        """Score a job and return full AI analysis."""
        prompt = f"""Analyze this freelance job for the given freelancer profile.

JOB DESCRIPTION:
{job_description[:3000]}

FREELANCER PROFILE:
- Skills: {', '.join(profile.get('skills', []))}
- Niche: {profile.get('preferred_niches', [])}
- Experience: {profile.get('experience_level')}
- Hourly rate: ${profile.get('hourly_rate_usd', 0)}/hr

Return a JSON object with these exact keys:
{{
  "match_score": <0-100 integer>,
  "win_probability": <0-100 float>,
  "skill_gaps": ["..."],
  "client_pain_points": ["..."],
  "project_complexity": "low|medium|high",
  "suggested_rate": <number in USD>,
  "suggested_tone": "conversational|technical|formal",
  "risk_level": "low|medium|high",
  "scam_score": <0-100 integer>,
  "priority": "high|medium|low",
  "recommended_action": "apply|skip|save",
  "key_selling_points": ["..."],
  "red_flags": ["..."],
  "estimated_hours": <number or null>
}}"""
        text, inp, out = await self.router.complete(
            prompt, JOB_ANALYSIS_SYSTEM, model="openai",
            temperature=0.2, json_mode=True
        )
        try:
            return json.loads(text)
        except Exception:
            return {"match_score": 50, "win_probability": 30, "error": "parse_failed"}

    async def generate_proposal(
        self,
        job: dict,
        profile: dict,
        style: str = "conversational",
        language: str = "en",
        memories: list[str] | None = None,
    ) -> tuple[str, dict]:
        """Generate a personalized proposal. Returns (text, quality_scores)."""

        memory_context = ""
        if memories:
            memory_context = "\n\nRELEVANT PAST SUCCESSES:\n" + "\n".join(f"- {m}" for m in memories[:5])

        style_instructions = {
            "conversational": "Write in a warm, direct, first-person tone. Short paragraphs. Natural flow.",
            "technical":      "Lead with technical expertise. Use specific technologies. Show deep understanding.",
            "sales":          "Focus on ROI and business value. Use power words. Strong benefits-focused CTA.",
            "enterprise":     "Professional and formal. Reference process, methodology, and risk management.",
            "short":          "Maximum 150 words. Only the most impactful points. Punchy and confident.",
        }

        prompt = f"""Write a {style} freelance proposal for this job.

JOB TITLE: {job.get('title')}
JOB DESCRIPTION: {job.get('description', '')[:2000]}
CLIENT BUDGET: ${job.get('budget_min', '?')}–${job.get('budget_max', '?')}
COMPETITION: {job.get('proposal_count', '?')} proposals submitted

FREELANCER:
- Name: {profile.get('name')}
- Skills: {', '.join(profile.get('skills', [])[:10])}
- Suggested rate: ${job.get('suggested_rate', profile.get('hourly_rate_usd', 0))}
- Key experience: {profile.get('bio', '')[:500]}
{memory_context}

STYLE GUIDANCE: {style_instructions.get(style, style_instructions['conversational'])}

Write the complete proposal now. Do not add headers or labels."""

        text, inp, out = await self.router.complete(
            prompt, ARABIC_SYSTEM_PROMPT if language == "ar" else PROPOSAL_SYSTEM, model="claude",
            temperature=0.8, max_tokens=800
        )

        # Quality evaluation
        quality = await self._evaluate_proposal_quality(text, job.get('description', ''))

        return text, {"tokens_in": inp, "tokens_out": out, **quality}

    async def _evaluate_proposal_quality(self, proposal: str, job_desc: str) -> dict:
        """Score proposal quality: personalization, readability, CTA strength."""
        prompt = f"""Rate this proposal on these dimensions (0-100 each).
Job description (first 500 chars): {job_desc[:500]}
Proposal: {proposal[:1000]}

Return JSON: {{"quality_score": N, "personalization_score": N, "readability": N, "cta_strength": N, "ai_detected": true/false}}"""
        text, _, _ = await self.router.complete(
            prompt, "Return only JSON.", model="openai",
            temperature=0.1, json_mode=True
        )
        try:
            return json.loads(text)
        except Exception:
            return {"quality_score": 70, "personalization_score": 65}

    async def generate_followup(self, context: dict) -> str:
        """Generate a natural follow-up message."""
        prompt = f"""Write a follow-up message for this situation:
- Job: {context.get('job_title')}
- Proposal submitted: {context.get('days_ago', '?')} days ago
- Status: {context.get('status', 'no response')}
- Client info: {context.get('client_name', 'the client')}
Keep it under 3 sentences. Sound natural."""
        text, _, _ = await self.router.complete(
            prompt, FOLLOWUP_SYSTEM, model="claude",
            temperature=0.9, max_tokens=200
        )
        return text.strip()

    async def optimize_profile(self, profile: dict) -> dict:
        """Return AI-optimized bio, headline, and skill suggestions."""
        prompt = f"""Optimize this freelancer profile for maximum visibility and conversion.

Current headline: {profile.get('headline', '')}
Current bio: {profile.get('bio', '')}
Skills: {', '.join(profile.get('skills', []))}
Target niches: {profile.get('preferred_niches', [])}

Return JSON:
{{
  "optimized_headline": "...",
  "optimized_bio": "...",
  "suggested_skills": ["..."],
  "keyword_density_score": 0-100,
  "profile_score": 0-100,
  "improvement_tips": ["..."]
}}"""
        text, _, _ = await self.router.complete(
            prompt, "You are a freelance profile SEO expert.", model="openai",
            temperature=0.5, json_mode=True
        )
        try:
            return json.loads(text)
        except Exception:
            return {"error": "optimization_failed"}

    async def get_relevant_memories(
        self, workspace_id: str, query: str, limit: int = 5
    ) -> list[str]:
        """Retrieve semantically relevant AI memories for a workspace."""
        query_embedding = await self.embedder.embed(query)
        # Vector similarity search via repository
        memories = await self.prop_repo.search_memories(
            workspace_id=workspace_id,
            embedding=query_embedding,
            limit=limit,
        )
        return [m.content for m in memories]

    async def store_memory(
        self,
        workspace_id: str,
        profile_id: str,
        memory_type: str,
        content: str,
    ) -> None:
        """Store a new AI memory with its embedding."""
        embedding = await self.embedder.embed(content)
        await self.prop_repo.save_memory(
            workspace_id=workspace_id,
            profile_id=profile_id,
            memory_type=memory_type,
            content=content,
            embedding=embedding,
        )
