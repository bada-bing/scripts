#!/usr/bin/env node

const fs = require('fs');
const { parseTaskProgress } = require('./logseq_parser.js');

/**
 * Applies the intended changes to the file content.
 * @param {object} targetItem The item to be completed.
 * @param {Array<string>} originalLines The array of all lines from the file.
 * @param {Array<object>} steps The structured array of all parsed steps.
 * @returns {Array<string>|null} A new array of lines with changes applied, or null if no target item found.
 */
function applyChanges(targetItem, originalLines, steps) {
    if (!targetItem) {
        console.log('No target task found.');
        return null;
    }

    const newLines = [...originalLines];
    let changesMade = false;
    const linesToMarkDone = new Set();

    // Identify the primary target task to be marked as DONE
    if (targetItem.status !== 'DONE') {
        linesToMarkDone.add(targetItem.lineNumber);
    }

    // If it's a milestone, identify all previous tasks to be marked as DONE
    if (targetItem.description.includes('✅ M')) {
        console.log('\n✨ This is a milestone task! Completing previous tasks in this step...');
        const parentStep = steps.find(step => step.items.some(item => item.lineNumber === targetItem.lineNumber));
        const targetItemIndex = parentStep.items.findIndex(item => item.lineNumber === targetItem.lineNumber);

        for (let i = 0; i < targetItemIndex; i++) {
            const itemToComplete = parentStep.items[i];
            if (itemToComplete.status !== 'DONE') {
                linesToMarkDone.add(itemToComplete.lineNumber);
            }
        }
    }

    // Apply all DONE changes
    linesToMarkDone.forEach(lineNumber => {
        const originalLine = newLines[lineNumber];
        // Ensure we replace the specific status, not just any word
        const statusRegex = new RegExp(`^(\\s*-\\s+)${originalLines[lineNumber].trim().split(' ')[1]}`);
        newLines[lineNumber] = originalLine.replace(statusRegex, `$1DONE`);
        changesMade = true;
    });

    // Promote the next LATER task to NOW, if applicable
    const parentStep = steps.find(step => step.items.some(item => item.lineNumber === targetItem.lineNumber));
    const targetItemIndex = parentStep.items.findIndex(item => item.lineNumber === targetItem.lineNumber);

    for (let i = targetItemIndex + 1; i < parentStep.items.length; i++) {
        const nextItem = parentStep.items[i];
        // Check if its original status was LATER and it wasn't just marked DONE
        if (nextItem.status === 'LATER' && !linesToMarkDone.has(nextItem.lineNumber)) {
            newLines[nextItem.lineNumber] = newLines[nextItem.lineNumber].replace('LATER', 'NOW');
            console.log(`\n🚀 Promoting next task to NOW...`);
            changesMade = true;
            break; // Promote only the first one
        }
    }

    return changesMade ? newLines : null;
}


/**
 * Main function to execute the script logic.
 */
function main() {
    const filePath = process.argv[2];
    const taskDescription = process.argv[3];

    if (!filePath) {
        console.error("Usage: update_logseq_task_state.js <path_to_logseq_file> [\"task description\"]");
        process.exit(1);
    }

    if (!fs.existsSync(filePath)) {
        console.error(`Error: File not found at '${filePath}'`);
        process.exit(1);
    }

    try {
        const content = fs.readFileSync(filePath, 'utf-8');
        const originalLines = content.split('\n');
        const steps = parseTaskProgress(content);

        if (!steps) {
            console.log('Could not parse task progress section. No changes applied.');
            return;
        }

        let targetItem = null;
        if (taskDescription) {
            for (const step of steps) {
                targetItem = step.items.find(item => item.description === taskDescription);
                if (targetItem) break;
            }
            if (!targetItem) {
                console.log(`Task '${taskDescription}' not found. No changes applied.`);
                return;
            }
        } else {
            for (const step of steps) {
                targetItem = step.items.find(item => item.status === 'NOW');
                if (targetItem) break;
            }
            if (!targetItem) {
                console.log('No active "NOW" task found. No changes applied.');
                return;
            }
        }

        const updatedLines = applyChanges(targetItem, originalLines, steps);

        if (updatedLines) {
            const backupPath = `${filePath}.bak`;
            console.log(`\n⚠️ Making a backup of '${filePath}' to '${backupPath}'...`);
            fs.copyFileSync(filePath, backupPath);

            console.log(`Writing changes to '${filePath}'...`);
            fs.writeFileSync(filePath, updatedLines.join('\n'), 'utf-8');
            console.log('Changes applied successfully!');
        } else {
            console.log('No changes were needed or applied.');
        }

    } catch (error) {
        console.error(`Error processing file: ${error.message}`);
        process.exit(1);
    }
}

main();
