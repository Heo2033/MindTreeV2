import { useEffect } from "react";
import { Routes, Route } from "react-router-dom";
import { HomeScreen } from "./screens/Home";
import { NewTopicScreen } from "./screens/NewTopic";
import { TopicShell } from "./screens/TopicShell";
import { GraphScreen } from "./screens/Graph";
import { FocusScreen } from "./screens/Focus";
import { SessionScreen } from "./screens/Session";
import { QuizScreen } from "./screens/Quiz";
import { TutorScreen } from "./screens/Tutor";
import { LearnerModelScreen } from "./screens/LearnerModel";
import { DiagnosticScreen } from "./screens/Diagnostic";
import { MilestonesScreen } from "./screens/Milestones";
import { ReviewScreen } from "./screens/Review";
import { FinalAssessmentScreen } from "./screens/FinalAssessment";
import { AnalyticsScreen } from "./screens/Analytics";
import { SettingsScreen } from "./screens/Settings";
import { configApi } from "./api";
import { fetchKey, loadMindTreeSettings } from "@mindtree/tauri-common";

export { setApiBase, setAuthToken } from "./api/client";

const SECRET_KEY_ID = "default";

export default function App() {
  useEffect(() => {
    void (async () => {
      try {
        const s = await configApi.get();
        if (s.effective.apiKeyConfigured) return;
        const stored = await fetchKey(SECRET_KEY_ID).catch(() => null);
        if (!stored) return;
        const local = await loadMindTreeSettings().catch(() => null);
        if (local?.provider === "ollama") return;
        await configApi.apply({ apiKey: stored });
      } catch {
        // ключ применится при открытии экрана настроек
      }
    })();
  }, []);

  return (
    <Routes>
      <Route path="/" element={<HomeScreen />} />
      <Route path="/new" element={<NewTopicScreen />} />
      <Route path="/settings" element={<SettingsScreen />} />
      <Route path="/topic/:topicId" element={<TopicShell />}>
        <Route index element={<GraphScreen />} />
        <Route path="graph" element={<GraphScreen />} />
        <Route path="focus" element={<FocusScreen />} />
        <Route path="session" element={<SessionScreen />} />
        <Route path="quiz" element={<QuizScreen />} />
        <Route path="tutor" element={<TutorScreen />} />
        <Route path="learner" element={<LearnerModelScreen />} />
        <Route path="diagnostic" element={<DiagnosticScreen />} />
        <Route path="milestones" element={<MilestonesScreen />} />
        <Route path="review" element={<ReviewScreen />} />
        <Route path="analytics" element={<AnalyticsScreen />} />
        <Route path="final" element={<FinalAssessmentScreen />} />
      </Route>
    </Routes>
  );
}