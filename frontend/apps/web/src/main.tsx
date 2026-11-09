import React from "react";
import ReactDOM from "react-dom/client";
import App from "./App";
import "./styles.css";
import { loadPublicRuntimeConfig } from "./runtime-config";

loadPublicRuntimeConfig().then(() => {
  ReactDOM.createRoot(document.getElementById("root")!).render(<App />);
}).catch(() => {
  document.getElementById("root")!.textContent = "Unable to load the application identity configuration. Contact the operator.";
});
