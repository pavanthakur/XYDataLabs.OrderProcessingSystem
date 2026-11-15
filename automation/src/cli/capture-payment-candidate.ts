import path from "node:path";
import {fileURLToPath} from "node:url";
import {candidateIdentity} from "../support/azure-matrix-checkpoint.js";
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),"../../..");
process.stdout.write(await candidateIdentity(root));
