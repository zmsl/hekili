#!/usr/bin/env node

const fs = require('fs');
const path = require('path');

function replaceTokens(str, variables) {
    return str.replace(/{{([\w\d]+)}}/g, (_, token) => {
        if (token in variables) {
            return `(${variables[token]})`;
        } else {
            throw new Error(`Undefined variable: {{${token}}}`);
        }
    });
}

function processTemplate(inputFile, outputFile) {
    if (inputFile === outputFile) {
        throw new Error("Input and output filenames must be different.");
    }
    if (!fs.existsSync(inputFile)) {
        throw new Error(`File not found: ${inputFile}`);
    }

    const content = fs.readFileSync(inputFile, 'utf-8');
    const lines = content.split('\n');

    const variables = {};
    const processedLines = [];
    let pushReady = false;

    for (const line of lines) {
        const match = line.match(/#\s*([\w\d]+)=(.+)/);
        if (match) {
            // console.log(`var: ${line}`)
            const [, key, rawValue] = match;
            const processedValue = replaceTokens(rawValue, variables);
            variables[key.trim()] = processedValue.trim();
        } else {
            // console.log(`apl: ${line}`)
            const processedLine = replaceTokens(line, variables);
            if (processedLine.trim() || pushReady) {
                processedLines.push(processedLine);
                if (processedLine.trim()) {
                    pushReady = true;
                }
            }
        }
    }

    fs.writeFileSync(outputFile, processedLines.join('\n'), 'utf-8');
    console.log(`File processed and saved to: ${outputFile}`);
}

function processDirectory() {
    const scriptDir = __dirname;
    const inputFiles = fs.readdirSync(scriptDir).filter(file => file.endsWith('.t.simc'));

    if (inputFiles.length === 0) {
        console.error("No files matching the pattern *.t.simc found in the script directory.");
        process.exit(1);
    }

    inputFiles.forEach(inputFile => {
        const inputPath = path.join(scriptDir, inputFile);
        const outputPath = path.join(scriptDir, inputFile.replace('.t.simc', '.simc'));
        try {
            processTemplate(inputPath, outputPath);
        } catch (error) {
            console.error(`Error processing ${inputFile}: ${error.message}`);
        }
    });
}

const args = process.argv.slice(2);
if (args.length === 0) {
    processDirectory();
} else if (args.length === 2) {
    const [inputFile, outputFile] = args;
    try {
        processTemplate(inputFile, outputFile);
    } catch (error) {
        console.error(`Error: ${error.message}`);
        process.exit(1);
    }
} else {
    console.error("Usage: node template.js <inputFile> <outputFile>");
    console.error("       node template.js (to process all *.t.simc files in the script directory)");
    process.exit(1);
}