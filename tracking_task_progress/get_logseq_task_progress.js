#!/usr/bin/env node

const fs = require("fs");
const { parseTaskProgress } = require("./logseq_parser.js");

/**
 * Main function to execute the script logic.
 */
function main() {
  const filePath = process.argv[2];
  if (!filePath) {
    console.error("Usage: get_logseq_task_progress.js <path_to_logseq_file>");
    process.exit(1);
  }

  try {
    const content = fs.readFileSync(filePath, "utf-8");
    const taskProgress = parseTaskProgress(content);
    if (taskProgress) {
      displayTaskProgress(taskProgress);
    }
  } catch (error) {
    // Fail silently if file not found or other read error.
  }
}

/**
 * Displays the formatted task progress summary.
 * @param {Array} steps - A structured array of steps and their items.
 */
function displayTaskProgress(steps) {
  // First, find all NOW tasks to check for duplicates
  const allNowTasks = steps.flatMap((step) =>
    step.items
      .filter((item) => item.status === "NOW")
      .map((item) => ({ ...item, stepTitle: step.title }))
  );

  if (allNowTasks.length > 1) {
    console.warn('\n⚠️ WARNING: Multiple "NOW" tasks are active!');
    allNowTasks.forEach((task) => {
      console.warn(`  - In step "${task.stepTitle}": ${task.description}`);
    });
  }

  const activeStep = steps.find((step) =>
    step.items.some((item) => item.status === "NOW")
  );

  if (!activeStep) {
    console.log("No active action items found.");
    return;
  }

  const activeItem = activeStep.items.find((item) => item.status === "NOW");
  const otherItems = activeStep.items.filter((item) => item.status !== "NOW");

  console.log(`\n🎯 Current Step: ${activeStep.title}`);
  console.log(`  - NOW: ${activeItem.description}`);

  if (otherItems.length > 0) {
    const counts = otherItems.reduce((acc, item) => {
      acc[item.status] = (acc[item.status] || 0) + 1;
      return acc;
    }, {});

    const summary = Object.entries(counts)
      .map(([status, count]) => `${count} ${status}`)
      .join(", ");

    console.log(`  (${summary})`);
  }
}

main();
