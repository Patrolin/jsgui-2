import { div, span, svg, button, input, useState, renderBody, rerender } from "../jsgui.mjs";

/**
 * @param {Component} header */
function headerLeft(header) {
  svg(
    header,
    { fontSize: 24 },
    `<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 0 24 24" width="24" focusable="false"><path d="M21 6H3V5h18v1zm0 5H3v1h18v-1zm0 6H3v1h18v-1z"></path></svg>`
  );
}
/**
 * @param {Component} header */
function headerMiddle(header) {
  const searchWrapper = div(header, { flex: "x" });
  input(searchWrapper, "text", {
    height: 40,
    borderRadius: "20px 0 0 20px",
    border: "1px solid rgb(48, 48, 48)",
    background: "none",
    padding: "0 0 0 16px",
    fontFamily: "Roboto, Arial, sans-serif",
    fontSize: 16,
    color: "white",
  });
  const searchButton = div(searchWrapper, {
    width: 64,
    height: 40,
    borderRadius: "0 20px 20px 0",
    background: "rgb(48, 48, 48)",
    flex: "x",
  });
  svg(
    searchButton,
    { fontSize: 24 },
    `<svg xmlns="http://www.w3.org/2000/svg" fill="currentColor" height="24" viewBox="0 0 24 24" width="24" focusable="false"><path clip-rule="evenodd" d="M16.296 16.996a8 8 0 11.707-.708l3.909 3.91-.707.707-3.909-3.909zM18 11a7 7 0 00-14 0 7 7 0 1014 0z" fill-rule="evenodd"></path></svg>`
  );

  const voiceButton = div(searchWrapper, {
    margin: "0 0 0 12px",
    width: 40,
    height: 40,
    borderRadius: 20,
    background: "rgb(48, 48, 48)",
    flex: "x",
  });
  svg(
    voiceButton,
    { fontSize: 24 },
    `<svg xmlns="http://www.w3.org/2000/svg" height="24" viewBox="0 0 24 24" width="24" focusable="false"><path d="M12 3c-1.66 0-3 1.37-3 3.07v5.86c0 1.7 1.34 3.07 3 3.07s3-1.37 3-3.07V6.07C15 4.37 13.66 3 12 3zm6.5 9h-1c0 3.03-2.47 5.5-5.5 5.5S6.5 15.03 6.5 12h-1c0 3.24 2.39 5.93 5.5 6.41V21h2v-2.59c3.11-.48 5.5-3.17 5.5-6.41z"></path></svg>`
  );
}
/**
 * @param {Component} header */
function headerRight(header) {
  div(header);
}
/**
 * @param {Component} body */
function App(body) {
  const [state, changeState] = useState(body, "App");

  const header = div(body, { width: "100%", height: 56, padding: "0 16px", flex: "x", flexAlign: "justify" });
  if (state.lineCount == null) {
    state.lineCount = 2;
  }

  headerLeft(header);
  headerMiddle(header);
  headerRight(header);

  const main = div(body, { width: "100%", padding: "8px 24px", flex: "x", flexAlign: "start", columnGap: 16 });
  const mainLeft = div(main, { flex: "y" });
  for (let i = 0; i < state.lineCount; i++) {
    span(mainLeft, { width: "100%" }, `Lorem ipsum ${state.lineCount + i}`);
  }
  for (let i = 0; i < state.lineCount; i++) {
    span(mainLeft, { width: "100%" }, `Lorem ipsum ${state.lineCount + i}`);
  }

  const mainRight = div(main, { flex: "y" });
  if (button(mainRight, { width: 64, height: 24 }, "Hello").pressed) {
    state.lineCount += 1;
    rerender();
  }
}
renderBody(App, { background: "#0f0f0f", scrollY: true, color: "white" });
