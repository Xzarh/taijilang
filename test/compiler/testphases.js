var LIST, SYMBOL, ShiftStatementInfo, SymbolLookupError, VALUE, constant, convert, expect, idescribe, iit, lib, metaConvert, ndescribe, nit, nonMetaCompileExpNoOptimize, norm, str, strConvert, strMetaConvert, strNonOptCompile, taiji, transformExpression, _ref, _ref1, _ref2, _ref3;

_ref = require('../utils'), expect = _ref.expect, idescribe = _ref.idescribe, ndescribe = _ref.ndescribe, iit = _ref.iit, nit = _ref.nit, strConvert = _ref.strConvert, str = _ref.str;

lib = '../../lib/';

_ref1 = require(lib + 'compiler/transform'), transformExpression = _ref1.transformExpression, ShiftStatementInfo = _ref1.ShiftStatementInfo;

_ref2 = require(lib + 'utils'), constant = _ref2.constant, norm = _ref2.norm;

VALUE = constant.VALUE, SYMBOL = constant.SYMBOL, LIST = constant.LIST;

_ref3 = require(lib + 'compiler'), convert = _ref3.convert, metaConvert = _ref3.metaConvert, nonMetaCompileExpNoOptimize = _ref3.nonMetaCompileExpNoOptimize;

SymbolLookupError = require(lib + 'compiler/env').SymbolLookupError;

taiji = require(lib + 'taiji');

strConvert = function(exp) {
  var env;
  exp = norm(exp);
  env = taiji.initEnv(taiji.builtins, taiji.rootModule, {});
  env.metaIndex = 0;
  exp = convert(exp, env);
  return str(exp);
};

strMetaConvert = function(exp) {
  var env, metaExpList;
  exp = norm(exp);
  env = taiji.initEnv(taiji.builtins, taiji.rootModule, {});
  env.metaIndex = 0;
  exp = metaConvert(exp, metaExpList = [], env);
  return str(exp);
};

strNonOptCompile = function(exp) {
  var env;
  exp = norm(exp);
  env = taiji.initEnv(taiji.builtins, taiji.rootModule, {});
  exp = nonMetaCompileExpNoOptimize(exp, env);
  return str(exp);
};

describe("test phases: ", function() {
  describe("convert: ", function() {
    describe("convert simple: ", function() {
      it("convert 1", function() {
        return expect(strConvert(1)).to.equal('1');
      });
      it('convert \'"hello"\' ', function() {
        return expect(strConvert('"hello"')).to.equal("\"hello\"");
      });
      return it('convert \'x\' ', function() {
        return expect(function() {
          return strConvert('x');
        }).to["throw"](SymbolLookupError);
      });
    });
    describe("convert if: ", function() {
      it("convert [if, 1, [1]]", function() {
        return expect(strConvert(['if', 1, [1]])).to.equal("[if 1 [1]]");
      });
      return it("convert [if, 1, [1], [2]]", function() {
        return expect(strConvert(['if', 1, [1], [2]])).to.equal("[if 1 [1] [2]]");
      });
    });
    return describe("convert binary!", function() {
      return it("convert ['binary!', '+', 1, 2]", function() {
        return expect(strConvert(['binary!', '+', 1, 2])).to.equal('[binary! + 1 2]');
      });
    });
  });
  describe("meta convert: ", function() {
    return describe("convert simple: ", function() {
      return it("convert 1", function() {
        return expect(strMetaConvert(1)).to.equal("[index! [jsvar! __tjExp] 0]");
      });
    });
  });
  describe("nonMetaCompileExpNoOptimize: ", function() {
    return describe("copmile simple: ", function() {
      it("copmile 1", function() {
        return expect(strNonOptCompile(1)).to.equal("1");
      });
      it("copmile '\"1\"' ", function() {
        return expect(strNonOptCompile('"1"')).to.equal("\"1\"");
      });
      return it("copmile ['binary!', '+', 1, 2] ", function() {
        return expect(strNonOptCompile(['binary!', '+', 1, 2])).to.equal("1 + 2");
      });
    });
  });
  return describe("transformExpression: ", function() {
    return iit("return 'a'", function() {
      var env, info, result;
      env = taiji.initEnv(taiji.builtins, taiji.rootModule, {});
      info = new ShiftStatementInfo({}, {});
      result = transformExpression(norm(['return', 'a']), env, info);
      expect(str(result[0])).to.equal("[return a]");
      expect(info.affectVars['a']).to.equal(void 0);
      return expect(info.shiftVars['a']).to.equal(true);
    });
  });
});