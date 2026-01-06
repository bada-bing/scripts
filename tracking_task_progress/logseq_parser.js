/**
 * @module logseq_parser
 * This module provides functions to parse Logseq markdown files.
 */

/**
 * Parses the content of a Logseq file to extract task progress information.
 * @param {string} content - The full content of the file.
 * @returns {Array|null} A structured representation of steps and their action items, or null if not found.
 */
function parseTaskProgress(content) {
  const lines = content.split("\n");
  const progressSectionStartIndex = lines.findIndex((line) =>
    line.includes("## Task Progress")
  );

  if (progressSectionStartIndex === -1) {
    return null; // No task progress section found
  }

  const progressSectionEndIndex = lines.findIndex(
    (line, index) =>
      index > progressSectionStartIndex && line.match(/^\s*-\s+##\s+[^#]/) // Match - ## but not - ### or - ####
  );

  const steps = [];
  let currentStep = null;

  const stepRegex = /^\s*-\s+####\s+(.*)/;
  const actionItemRegex = /^\s*-\s+(DONE|NOW|LATER|WAITING)\s+(.*)/;

  // iterate over the original `lines` to get correct line numbers
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];

    // Only process lines that are inside the task progress section
    if (i <= progressSectionStartIndex) continue;
    if (progressSectionEndIndex > -1 && i >= progressSectionEndIndex) break;

    const stepMatch = line.match(stepRegex);
    if (stepMatch) {
      currentStep = {
        title: stepMatch[1].trim(),
        items: [],
      };
      steps.push(currentStep);
      continue;
    }

    const actionItemMatch = line.match(actionItemRegex);
    if (actionItemMatch && currentStep) {
      currentStep.items.push({
        status: actionItemMatch[1],
        description: actionItemMatch[2].trim(),
        lineNumber: i,
      });
    }
  }

  return steps.length > 0 ? steps : null;
}

module.exports = { parseTaskProgress };
