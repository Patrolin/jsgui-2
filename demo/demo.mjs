import { div, span, button, useState, renderBody, rerender } from "../src/jsgui.mjs";

/**
 * @param {Component} body */
function App(body) {
  const state = useState(body, "App", {
    clicks: 0,
  });

  const row = div(body, {padding: 8, flex: "x", columnGap: 8});
  span(row, `Clicks: ${state.clicks}`);
  if (button(row, "Press me!", {margin: "0"}).pressed) {
    state.clicks += 1
    rerender();
  }
}
renderBody(App, { scrollY: true });
