import Login from "./login";
import Home from "./home";
import Settings from "./settings";
import { BrowserRouter as Router, Routes, Route } from "react-router-dom";
import ProtectedRoute from "./components/protectedroutes";

function App() {

  return (
      <Router>
        <Routes>
          <Route path="/" element={<Login />} />
          <Route path="/home" element={<ProtectedRoute><Home /></ProtectedRoute>} />
          <Route path="/settings" element={<ProtectedRoute><Settings /></ProtectedRoute>} />
        </Routes>
      </Router>
  )
}

export default App
