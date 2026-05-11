-- ============================================================
-- FreelancePilot AI — Row Level Security Policies
-- Every table is workspace-isolated
-- ============================================================

ALTER TABLE workspaces          ENABLE ROW LEVEL SECURITY;
ALTER TABLE workspace_members   ENABLE ROW LEVEL SECURITY;
ALTER TABLE freelancer_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE scraped_jobs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE job_matches         ENABLE ROW LEVEL SECURITY;
ALTER TABLE proposals           ENABLE ROW LEVEL SECURITY;
ALTER TABLE clients             ENABLE ROW LEVEL SECURITY;
ALTER TABLE applications        ENABLE ROW LEVEL SECURITY;
ALTER TABLE interviews          ENABLE ROW LEVEL SECURITY;
ALTER TABLE conversations       ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_memories         ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_configs  ENABLE ROW LEVEL SECURITY;
ALTER TABLE automation_logs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications       ENABLE ROW LEVEL SECURITY;
ALTER TABLE analytics_events    ENABLE ROW LEVEL SECURITY;
ALTER TABLE ai_usage            ENABLE ROW LEVEL SECURITY;
ALTER TABLE subscriptions       ENABLE ROW LEVEL SECURITY;

-- Helper: check if current user is member of a workspace
CREATE OR REPLACE FUNCTION is_workspace_member(ws_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = ws_id
      AND user_id = auth.uid()
      AND accepted_at IS NOT NULL
  );
$$;

-- Helper: check if user has admin role
CREATE OR REPLACE FUNCTION is_workspace_admin(ws_id uuid)
RETURNS boolean LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT EXISTS (
    SELECT 1 FROM workspace_members
    WHERE workspace_id = ws_id
      AND user_id = auth.uid()
      AND role IN ('workspace_owner','admin')
      AND accepted_at IS NOT NULL
  );
$$;

-- WORKSPACES: members can see their workspaces, owners can update
CREATE POLICY ws_select ON workspaces FOR SELECT USING (is_workspace_member(id));
CREATE POLICY ws_insert ON workspaces FOR INSERT WITH CHECK (true);
CREATE POLICY ws_update ON workspaces FOR UPDATE USING (is_workspace_admin(id));

-- WORKSPACE_MEMBERS
CREATE POLICY wm_select ON workspace_members FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY wm_insert ON workspace_members FOR INSERT WITH CHECK (is_workspace_admin(workspace_id));
CREATE POLICY wm_delete ON workspace_members FOR DELETE USING (
  user_id = auth.uid() OR is_workspace_admin(workspace_id)
);

-- All other tables: select/insert/update/delete by workspace membership
CREATE POLICY fp_select ON freelancer_profiles FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY fp_insert ON freelancer_profiles FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY fp_update ON freelancer_profiles FOR UPDATE USING (is_workspace_member(workspace_id));
CREATE POLICY fp_delete ON freelancer_profiles FOR DELETE USING (is_workspace_admin(workspace_id));

CREATE POLICY sj_select ON scraped_jobs FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY sj_insert ON scraped_jobs FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

CREATE POLICY jm_select ON job_matches FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY jm_insert ON job_matches FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY jm_update ON job_matches FOR UPDATE USING (is_workspace_member(workspace_id));

CREATE POLICY pr_select ON proposals FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY pr_insert ON proposals FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY pr_update ON proposals FOR UPDATE USING (is_workspace_member(workspace_id));

CREATE POLICY cl_select ON clients FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY cl_insert ON clients FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY cl_update ON clients FOR UPDATE USING (is_workspace_member(workspace_id));

CREATE POLICY ap_select ON applications FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY ap_insert ON applications FOR INSERT WITH CHECK (is_workspace_member(workspace_id));
CREATE POLICY ap_update ON applications FOR UPDATE USING (is_workspace_member(workspace_id));

CREATE POLICY nt_select ON notifications FOR SELECT USING (user_id = auth.uid());
CREATE POLICY nt_update ON notifications FOR UPDATE USING (user_id = auth.uid());

CREATE POLICY ae_select ON analytics_events FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY ae_insert ON analytics_events FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

CREATE POLICY au_select ON ai_usage FOR SELECT USING (is_workspace_member(workspace_id));
CREATE POLICY au_insert ON ai_usage FOR INSERT WITH CHECK (is_workspace_member(workspace_id));

CREATE POLICY sub_select ON subscriptions FOR SELECT USING (is_workspace_member(workspace_id));
