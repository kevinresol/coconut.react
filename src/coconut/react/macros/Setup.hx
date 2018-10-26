package coconut.react.macros;

#if macro
import coconut.ui.macros.*;
import haxe.macro.*;
import haxe.macro.Expr;
using haxe.macro.Tools;
using tink.MacroApi;

class Setup {
  
  static function hxxAugment() {
    var cls = Context.getLocalClass().get(),
        fields = Context.getBuildFields();

    switch cls {
      case { name: 'View', pack: ['coconut', 'ui'] }:
        for (f in fields)
          if (f.name == 'forceUpdate')
            f.access.push(AOverride);
        return fields;
      default:
    }

    for (f in fields)
      if (f.name == 'fromHxx') return null;

    function without(type:haxe.macro.Type, name:String):tink.core.Outcome<haxe.macro.Type, tink.core.Error> {
      return switch type.reduce() {
        case TAnonymous(_.get().fields => fields):
          var fields = fields.filter(function(field) return field.name != name);
          ComplexType.TAnonymous([for(f in fields) {
            meta: f.meta.get(),
            kind: FVar(f.type.toComplex()),
            name: f.name,
            pos: f.pos,
          }]).toType();
        case TDynamic(null):
          Success(type);
        case v:
          Failure(new tink.core.Error('Cannot remove field from $v'));
      }
    }
    
    var type = TPath(cls.name.asTypePath([for (p in cls.params) TPType(p.name.asComplexType())]));
    var props = switch without((macro (null:$type).props).typeof().sure(), 'children').sure() {
      case TDynamic(null): macro : Dynamic;
      case t: [
        t.toComplex(),
        macro : {
          @:optional var key(default, never):coconut.react.Key;
        }
      ].intersect().sure();
    }
    
    function infer() {
      return (macro (props : $props));
    }

    var add = (switch (macro (null:$type).props.children).typeof() {
      case Success(_.toComplex() => children):
        macro class {
          inline static public function fromHxx(props:$props, ?children:$children):react.ReactComponent.ReactSingleFragment {
            ${infer.bounce()};
            return (cast react.React.createElement).apply(react.React, [$i{cls.name}, untyped props].concat(untyped children));
          }
        }
      case Failure(_):
        macro class {
          inline static public function fromHxx(props:$props):react.ReactComponent.ReactSingleFragment {
            ${infer.bounce()};
            return cast react.React.createElement($i{cls.name}, props);
          }
        }
    }).fields;

    {
      var fromHxx = (add[0]:Member).getFunction().sure();
      fromHxx.params = [
        for (p in cls.params) { 
          name: p.name, 
          constraints: switch p.t {
            case TInst(_.get().kind => KTypeParameter(constraints), _):
              [for (c in constraints) c.toComplex()];
            default: throw 'assert';
          }
        }
      ];
    }

    return fields.concat(add);
  }

  static function all() {
    HXX.generator = new Generator(
      tink.hxx.Generator.extractTags(macro coconut.react.Html)
    );

    Compiler.addGlobalMetadata('coconut.ui.View', '@:ignore_empty_render', false);

    var comp = Context.getType('react.ReactComponent').getClass();

    if (!comp.meta.has(':hxxAugmented')) {//TODO: just move this to haxe-react
      comp.meta.add(':hxxAugmented', [], (macro null).pos);
      comp.meta.add(':autoBuild', [macro coconut.react.macros.Setup.hxxAugment()], (macro null).pos);
    }

    coconut.ui.macros.ViewBuilder.afterBuild.whenever(function (ctx) {
      var cls = ctx.target.target;

      for (m in ctx.target)
        if (m.name == 'state')
          m.pos.error('Name `state` is reserved in coconut.react. Consider using `currentState` instead.');
      
      var self = '${cls.module}.${cls.name}'.asComplexType([
        for (p in cls.params) TPType(p.name.asComplexType())
      ]);

      var attributes = TAnonymous(ctx.attributes.concat(
        (macro class {
          @:optional var key(default, never):coconut.react.Key;
          @:optional var ref(default, never):$self->Void;
        }).fields      
      ));

      {
        var render = ctx.target.memberByName('render').sure();
        render.addMeta(':native', [macro 'coconutRender']);
        render.overrides = true;
      }

      var states = [];
      var stateMap = EObjectDecl(states).at();
      for (s in ctx.states) {
        var s = s.name;
        states.push({
          field: s,
          expr: macro function () return this.$s,
        });
      }

      #if react_devtools
      ctx.target.getConstructor().addStatement(macro this.__stateMap = $stateMap);
      #end
      ctx.target.addMembers(macro class {
        #if react_devtools
        @:keep @:noCompletion var __stateMap:{};
        #end
        static public function fromHxx(attributes:$attributes):coconut.react.ViewFragment<$self> {
          return cast react.React.createElement($i{ctx.target.target.name}, attributes);
        }
      });
    });    
  }
}
#end