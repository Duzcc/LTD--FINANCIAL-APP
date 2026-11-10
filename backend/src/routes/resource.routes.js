const express = require('express');
const resourceController = require('../controllers/resource.controller');
const asyncHandler = require('../middleware/async-handler');

module.exports = (name) => {
  const controller = resourceController(name);
  const router = express.Router();
  router.get('/', asyncHandler(controller.list));
  router.get('/:id', asyncHandler(controller.get));
  router.post('/', asyncHandler(controller.create));
  router.put('/:id', asyncHandler(controller.update));
  router.delete('/:id', asyncHandler(controller.remove));
  return router;
};
