# ============================================================
# FreelancePilot AI — Playwright Automation Engine
# apps/api/app/services/automation_service.py
# ANTI-BAN: Human-like behavior. Never spam.
# ============================================================

from __future__ import annotations
import asyncio, random, string
from datetime import datetime, timedelta
from typing import Optional
from playwright.async_api import async_playwright, Page, Browser, BrowserContext

from app.config import settings
from app.core.database import AsyncSession
from app.repositories.automation_repository import AutomationRepository


# ── Safety Constants ──────────────────────────────────────────

DAILY_LIMIT_PER_PLATFORM = 8
ARABIC_PLATFORM_DAILY_LIMIT = 5      # Max proposals per day per platform
MIN_DELAY_BETWEEN_ACTIONS = 4.0   # seconds
MAX_DELAY_BETWEEN_ACTIONS = 6.0   # seconds
TYPING_SPEED_WPM_MIN = 55
TYPING_SPEED_WPM_MAX = 90
READING_DELAY_PER_100_CHARS = 0.8  # seconds spent "reading"


# ── Human Simulation Utilities ────────────────────────────────

async def human_delay(min_s: float = None, max_s: float = None) -> None:
    """Random delay to simulate human thinking/reading."""
    lo = min_s or MIN_DELAY_BETWEEN_ACTIONS
    hi = max_s or MAX_DELAY_BETWEEN_ACTIONS
    await asyncio.sleep(random.uniform(lo, hi))


async def human_type(page: Page, selector: str, text: str) -> None:
    """Type text at human-like speed with occasional pauses."""
    await page.click(selector)
    await human_delay(0.3, 0.8)

    # Characters per second based on WPM range
    chars_per_min = random.randint(TYPING_SPEED_WPM_MIN * 5, TYPING_SPEED_WPM_MAX * 5)
    delay_per_char = 60 / chars_per_min

    for char in text:
        await page.keyboard.type(char)
        # Occasional longer pause (thinking / hesitation)
        if random.random() < 0.03:
            await asyncio.sleep(random.uniform(0.4, 1.2))
        else:
            await asyncio.sleep(delay_per_char * random.uniform(0.7, 1.3))


async def simulate_reading(text_length: int) -> None:
    """Simulate time spent reading content."""
    read_time = (text_length / 100) * READING_DELAY_PER_100_CHARS
    read_time = max(1.0, min(read_time, 8.0))  # clamp 1–8s
    await asyncio.sleep(random.uniform(read_time * 0.8, read_time * 1.2))


async def human_scroll(page: Page, direction: str = "down", amount: int = None) -> None:
    """Scroll naturally with variable speed."""
    px = amount or random.randint(200, 600)
    if direction == "up":
        px = -px
    await page.evaluate(f"window.scrollBy({{top: {px}, behavior: 'smooth'}})")
    await human_delay(0.5, 1.5)


# ── Browser Session Manager ───────────────────────────────────

class BrowserSessionManager:
    """Manage persistent browser contexts with proxy support."""

    def __init__(self):
        self._playwright = None
        self._browser: Optional[Browser] = None
        self._contexts: dict[str, BrowserContext] = {}

    async def start(self):
        self._playwright = await async_playwright().start()
        self._browser = await self._playwright.chromium.launch(
            headless=settings.PLAYWRIGHT_HEADLESS,
            args=[
                "--no-sandbox",
                "--disable-blink-features=AutomationControlled",
                "--disable-dev-shm-usage",
            ],
        )

    async def get_context(
        self,
        session_id: str,
        storage_state: dict | None = None,
        proxy: str | None = None,
    ) -> BrowserContext:
        if session_id not in self._contexts:
            kwargs: dict = {
                "viewport": {"width": random.choice([1280, 1366, 1440, 1920]), "height": random.choice([768, 900, 1080])},
                "user_agent": self._random_user_agent(),
                "locale": "en-US",
                "timezone_id": "America/New_York",
                "extra_http_headers": {
                    "Accept-Language": "en-US,en;q=0.9",
                },
            }
            if storage_state:
                kwargs["storage_state"] = storage_state
            if proxy:
                kwargs["proxy"] = {"server": proxy}
            ctx = await self._browser.new_context(**kwargs)
            # Remove automation detection markers
            await ctx.add_init_script("""
                Object.defineProperty(navigator, 'webdriver', {get: () => undefined});
                Object.defineProperty(navigator, 'plugins', {get: () => [1,2,3]});
                window.chrome = {runtime: {}};
            """)
            self._contexts[session_id] = ctx
        return self._contexts[session_id]

    async def close_context(self, session_id: str):
        if session_id in self._contexts:
            await self._contexts[session_id].close()
            del self._contexts[session_id]

    async def stop(self):
        for ctx in self._contexts.values():
            await ctx.close()
        if self._browser:
            await self._browser.close()
        if self._playwright:
            await self._playwright.stop()

    def _random_user_agent(self) -> str:
        uas = [
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:125.0) Gecko/20100101 Firefox/125.0",
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_4_1) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4.1 Safari/605.1.15",
        ]
        return random.choice(uas)


# ── Platform Automators ───────────────────────────────────────

class UpworkAutomator:
    """Upwork-specific browser automation."""

    BASE = "https://www.upwork.com"

    def __init__(self, context: BrowserContext):
        self.context = context

    async def insert_proposal(self, job_url: str, proposal_text: str) -> dict:
        """Navigate to a job and insert proposal text for human review."""
        page = await self.context.new_page()
        log = {"status": "started", "screenshots": [], "job_url": job_url}

        try:
            await page.goto(job_url, wait_until="domcontentloaded", timeout=30000)
            await human_delay(1.5, 3.0)

            # Read the job description (simulate human reading)
            job_desc_el = await page.query_selector(".air3-popper-content, .job-description")
            if job_desc_el:
                desc_text = await job_desc_el.inner_text()
                await simulate_reading(len(desc_text))

            await human_scroll(page, "down", 300)

            # Find "Submit a Proposal" button
            submit_btn = await page.wait_for_selector(
                "text=Submit a Proposal", timeout=10000
            )
            if not submit_btn:
                log["status"] = "no_submit_button"
                return log

            await human_delay(0.8, 1.5)
            await submit_btn.click()
            await page.wait_for_load_state("networkidle", timeout=15000)
            await human_delay(1.0, 2.0)

            # Find cover letter textarea
            cover_letter = await page.wait_for_selector(
                "textarea[placeholder*='cover letter'], textarea[name*='cover']",
                timeout=10000,
            )

            # Type the proposal with human-like speed
            await human_type(page, "textarea[placeholder*='cover letter'], textarea[name*='cover']", proposal_text)

            screenshot = await page.screenshot(type="png")
            log["screenshots"].append("proposal_filled.png")
            log["status"] = "filled_awaiting_approval"
            log["screenshot_data"] = screenshot

            # DO NOT AUTO-SUBMIT. Human must approve.
            # The automation stops here and waits for manual approval.

        except Exception as e:
            log["status"] = "error"
            log["error"] = str(e)
            try:
                s = await page.screenshot(type="png")
                log["error_screenshot"] = s
            except Exception:
                pass
        finally:
            await page.close()

        return log


# ── Main Automation Service ───────────────────────────────────

class AutomationService:

    def __init__(self, db: AsyncSession):
        self.db = db
        self.repo = AutomationRepository(db)
        self.session_manager = BrowserSessionManager()

    async def run_job_scan(self, workspace_id: str, config_id: str) -> dict:
        """
        Scan platforms for new matching jobs.
        This is a READ-ONLY operation — no form submissions.
        """
        config = await self.repo.get_config(config_id)
        if not config or not config.is_enabled:
            return {"status": "disabled"}

        results = {"scanned": 0, "new_jobs": 0, "errors": []}
        # Job scanning logic would call platform-specific scrapers
        # (separate from the proposal automation for safety isolation)
        await self.repo.log_action(
            workspace_id=workspace_id,
            config_id=config_id,
            action="job_scan",
            status="completed",
            metadata=results,
        )
        return results

    async def prepare_proposal_submission(
        self,
        workspace_id: str,
        proposal_id: str,
        job_url: str,
    ) -> dict:
        """
        Stage a proposal for human review before any submission.
        MANDATORY: require_approval must be True.
        """
        # Check daily limit
        today_count = await self.repo.get_today_count(workspace_id)
        if today_count >= DAILY_LIMIT_PER_PLATFORM:
            return {"status": "daily_limit_reached", "count": today_count}

        # Log the attempt
        log = await self.repo.log_action(
            workspace_id=workspace_id,
            action="proposal_staged",
            status="pending_approval",
            job_url=job_url,
        )

        return {
            "status": "staged",
            "requires_approval": True,
            "log_id": str(log.id),
            "message": "Proposal staged. Human approval required before submission.",
        }

    async def check_daily_safety(self, workspace_id: str) -> dict:
        """Return current automation usage and safety status."""
        count = await self.repo.get_today_count(workspace_id)
        return {
            "applications_today": count,
            "daily_limit": DAILY_LIMIT_PER_PLATFORM,
            "safe_to_proceed": count < DAILY_LIMIT_PER_PLATFORM,
            "remaining": max(0, DAILY_LIMIT_PER_PLATFORM - count),
        }
