package coconut.react.macros;

#if macro
import coconut.ui.macros.*;
import tink.SyntaxHub;
import tink.hxx.*;
import haxe.macro.*;
import haxe.macro.Type;
import haxe.macro.Expr;
using haxe.macro.Tools;
using tink.MacroApi;

class Setup {

  static function toComplex(cls:ClassType)
    return TPath(cls.name.asTypePath([for (p in cls.params) TPType(p.name.asComplexType())]));

  static function parametrize(m:Member, self:ClassType)
    m.getFunction().sure().params = [for (p in self.params) p.toDecl()];

  static function hxxAugment() {
    var cls = Context.getLocalClass().get(),
        fields = Context.getBuildFields();

    switch cls {
      case { name: 'View', pack: ['coconut', 'ui'] }:
        for (f in fields)
          if (f.name == 'forceUpdate')
            f.meta.push({ name: ':native', params: [macro "cocoForceUpdate"], pos: f.pos });
        return fields;
      default:
    }

    for (f in fields)
      if (f.name == 'fromHxx') return null;

    var type = toComplex(cls);

    var children = null,
        childrenOptional = true;//TODO: this flag is actually not evaluated

    var props = switch (macro (null:$type).props).typeof().sure().reduce() {
      case TDynamic(null):
        children = macro : coconut.ui.Children;
        macro : Dynamic;
      case TAnonymous(_.get().fields => fields):

        var ret:Array<Field> = [],
            hasRef = false,
            hasKey = false;

        for (f in fields)
          switch f.name {
            case 'children':

              childrenOptional = f.meta.has(':optional');
              children = f.type.toComplex();

            default:

              if (f.name == 'key')
                hasKey = true;

              if (f.name == 'ref')
                hasRef = true;

              ret.push({
                meta: f.meta.get(),
                kind: FVar(f.type.toComplex()),
                name: f.name,
                pos: f.pos,
              });
          }

        if (!hasRef)
          ret.push((macro class {
            @:optional var ref(default, never):coconut.ui.Ref<$type>;
          }).fields[0]);

        if (!hasKey)
          ret.push((macro class {
            @:optional var key(default, never):coconut.react.Key;
          }).fields[0]);

        TAnonymous(ret);
      case t:
        cls.pos.error('unsupported prop type $t');
    }

    var id = cls.isPrivate ? macro $i{cls.name} : macro $p{'${cls.module}.${cls.name}'.split('.')};
    var add = (
      if (children == null)
        macro class {
          inline static public function fromHxx(props:$props):react.ReactComponent.ReactSingleFragment
            return cast react.React.createElement($id, props);
        }
      else
        macro class {
          inline static public function fromHxx(props:$props, ?children:$children):react.ReactComponent.ReactSingleFragment
            return (cast react.React.createElement).apply(react.React, [($id:react.ReactType), untyped props].concat(untyped children));
        }
    ).fields;

    parametrize(add[0], cls);

    return fields.concat(add);
  }

  static function all() {

    Compiler.addGlobalMetadata('coconut.ui.View', '@:ignore_empty_render', false);

    var comp = Context.getType('react.ReactComponent').getClass();

    if (!comp.meta.has(':hxxAugmented')) {//TODO: just move this to haxe-react
      comp.meta.add(':hxxAugmented', [], (macro null).pos);
      comp.meta.add(':autoBuild', [macro coconut.react.macros.Setup.hxxAugment()], (macro null).pos);
    }

    Context.getType('coconut.ui.View').getFields();//Pretty whacky way to force typing order

    coconut.ui.macros.ViewBuilder.afterBuild.whenever(function (ctx) {
      var cls = ctx.target.target;

      for (m in ctx.target)
        if (m.name == 'state')
          m.pos.error('Name `state` is reserved in coconut.react. Consider using `currentState` instead.');

      var self = toComplex(cls);

      var attributes = TAnonymous(ctx.attributes.concat(
        (macro class {
          @:optional var key(default, never):coconut.react.Key;
          @:optional var ref(default, never):coconut.ui.Ref<$self>;
        }).fields
      ));

      {
        var render = ctx.target.memberByName('render').sure();
        render.addMeta(':native', [macro 'coconutRender']);
        var ctor = ctx.target.getConstructor();
        @:privateAccess switch ctor.meta { //TODO: this is rather horrible
          case null:
            ctor.meta = [{ name: ':keep', params: [], pos: ctor.pos }];
          case meta: 
            meta.push({ name: ':keep', params: [], pos: ctor.pos });
        }
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
      var added = ctx.target.addMembers(macro class {
        #if react_devtools
        @:keep @:noCompletion var __stateMap:{};
        #end
        static public function fromHxx(attributes:$attributes):coconut.ui.RenderResult {
          return cast react.React.createElement(cast $i{ctx.target.target.name}, attributes);
        }
      });
      parametrize(added[added.length - 1], cls);
    });
  }
  
  static function sugar() {
    SyntaxHub.classLevel.after('tink.lang.sugar.Hxx', function(c:ClassBuilder) {
      if(c.target.superClass != null && c.target.superClass.t.toString() == 'coconut.ui.View') {
        switch c.memberByName('render') {
          case Success(member = {kind: FFun(f)}):
            var exprs = Lambda.fold(
              member.metaNamed(':coconut.react.hook'), 
              function(hook, last:Array<Expr>) return last.concat(hook.params), 
              []
            );
            if(exprs.length > 0)
              trace('transforming ${c.target.name}::${member.name}');
              f.expr = macro {
                function Render() {
                  @:mergeBlock $b{exprs};
                  ${f.expr};
                }
                return react.ReactMacro.jsx('<Render/>');
              }
          case _:
        }
      }
      return false;
    }, 'coconut.react.macros.Setup::sugar');
  }
}
#end
