import { div, span, button, useState, renderBody } from "../src/jsgui.mjs";

/**
 * @param {Component} body */
function App(body) {
  const [state, changeState] = useState(body, "App", {
    clicks: 0,
  });

  const row = div(body, {padding: 8, flex: "x", columnGap: 8});
  span(row, {}, `Clicks: ${state.clicks}`);
  if (button(row, {margin: "0"}, "Press me!").pressed) {
    changeState({clicks: state.clicks + 1});
  }
}
renderBody(App, { background: "#0f0f0f", scrollY: true, color: "white" });
