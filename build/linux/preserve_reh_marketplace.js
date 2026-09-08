#!/usr/bin/env node
/*
 * Preserve an explicitly overridden extension gallery across REH upgrades.
 * Fresh servers and servers left on the bundled Open VSX config stay unchanged.
 */

'use strict';

const fs = require('fs');
const path = require('path');

const serverRoot = process.argv[2];
if (!serverRoot) {
	process.exit(0);
}

const currentProductPath = path.join(serverRoot, 'product.json');
const binRoot = path.dirname(serverRoot);
const defaultOpenVsxGallery = {
	serviceUrl: 'https://open-vsx.org/vscode/gallery',
	itemUrl: 'https://open-vsx.org/vscode/item',
	latestUrlTemplate: 'https://open-vsx.org/vscode/gallery/{publisher}/{name}/latest',
	controlUrl: 'https://raw.githubusercontent.com/EclipseFdn/publish-extensions/refs/heads/master/extension-control/extensions.json'
};

function readJson(filePath) {
	return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function isDefaultOpenVsxGallery(product) {
	const gallery = product?.extensionsGallery;
	if (!gallery || Object.keys(gallery).length !== Object.keys(defaultOpenVsxGallery).length) {
		return false;
	}

	return Object.entries(defaultOpenVsxGallery).every(([key, value]) => gallery[key] === value);
}

try {
	const currentProduct = readJson(currentProductPath);
	if (!isDefaultOpenVsxGallery(currentProduct)) {
		process.exit(0);
	}

	const candidates = fs.readdirSync(binRoot, { withFileTypes: true })
		.filter(entry => entry.isDirectory())
		.map(entry => {
			const root = path.join(binRoot, entry.name);
			return { root, mtime: fs.statSync(root).mtimeMs };
		})
		.filter(entry => path.resolve(entry.root) !== path.resolve(serverRoot))
		.sort((a, b) => b.mtime - a.mtime);

	for (const candidate of candidates) {
		const previousProductPath = path.join(candidate.root, 'product.json');
		if (!fs.existsSync(previousProductPath)) {
			continue;
		}

		const previousProduct = readJson(previousProductPath);
		if (isDefaultOpenVsxGallery(previousProduct)) {
			continue;
		}

		currentProduct.extensionsGallery = previousProduct.extensionsGallery;
		const temporaryPath = `${currentProductPath}.marketplace-tmp`;
		fs.writeFileSync(temporaryPath, `${JSON.stringify(currentProduct, null, '\t')}\n`, 'utf8');
		fs.renameSync(temporaryPath, currentProductPath);
		break;
	}
} catch (error) {
	console.error(`VSCodium: could not preserve the remote Marketplace selection: ${error.message}`);
}
