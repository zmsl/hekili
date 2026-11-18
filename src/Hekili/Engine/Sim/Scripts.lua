-- Scripts.lua
-- December 2014

local addon, ns = ...
local Hekili = _G[ addon ]

local class   = Hekili.Class
local scripts = Hekili.Scripts
local state   = Hekili.State

local GetResourceInfo, GetResourceID = ns.GetResourceInfo, ns.GetResourceID
local SpaceOut = ns.SpaceOut

local ceil = math.ceil
local orderedPairs = ns.orderedPairs
local roundUp = ns.roundUp
local safeMax = ns.safeMax

local format, trim = string.format, string.trim
local GetFileIDFromPath, issecretvalue = ns.Facade.GetFileIDFromPath, ns.Facade.issecretvalue

local twipe, insert = table.wipe, table.insert


-- Forgive the name, but this should properly replace ! characters with not, accounting for appropriate bracketing.
-- Why so complex?  Because "! 0 > 1" converted to Lua is "not 0 > 1" which evaluates to "false > 1" -- not the goal.
-- This should convert:
-- example 1:  ! 0 > 1
--             not ( 0 > 1 )
--
-- example 2:  ! ( 0 > 1 & ! ( false | true ) )
--             not ( 0 > 1 & not ( false | true ) )
--
-- example 3:  ! cooldown.x.remains > 1 * ( gcd * ( 8 % 3 ) )
--             not ( cooldown.x.remains > 1 * ( gcd * ( 8 % 3 ) ) )
--
-- Hopefully.

local exprBreak = {
   ["&"] = true,
   ["|"] = true,
}

local function forgetMeNots( str )
   -- First, handle already bracketed "!(X)" -> "not (X)".
   local found = 1

   while found > 0 do
      str, found = str:gsub( "%s*!%s*(%b())%s*", " not %1 " )
   end

   -- The remaining conditions are not bracketed, but may include brackets.
   -- Such as !5>2+(1*3).
   -- So we'll start from the !, then go through the string until it's time to stop.

   local substring

   while( str:find("!") ) do
      local start = str:find("!")

      local parens = 0
      local finish = -1

      for j = start, str:len() do
         local char = str:sub( j, j )

         if char == "(" then
            parens = parens + 1

         elseif char == ")" then
            if parens > 0 then parens = parens - 1
            else finish = j - 1; break end

         elseif parens == 0 then
            -- We are not within a bracketed part of the string.  We can end here.
            if exprBreak[ char ] then
               finish = j - 1
               break
            end
         end
      end

      if finish == -1 then finish = str:len() end

      substring = str:sub( start + 1, finish )
      substring = substring:trim()

      -- each pass turns one `!` into `not`, so the loop ends (CN25: a cap at 100 left the rest in the Lua text)
      str = format( "%s not ( %s ) %s", str:sub( 1, start - 1 ) or "", substring, str:sub( finish + 1, str:len() ) or "" )
   end

   str = str:gsub( "%s%s", " " )

   return str
end


local function atToAbs( str )
    -- First, handle already bracketed "!(X)" -> "not (X)".
    local found = 1

    while found > 0 do
       str, found = str:gsub( "%s*@%s*(%b())%s*", " abs(safenum%1) " )
    end

    -- The remaining conditions are not bracketed, but may include brackets.
    -- Such as !5>2+(1*3).
    -- So we'll start from the !, then go through the string until it's time to stop.

    local i = 1
    local substring

    while( str:find("@") ) do
       local start = str:find("@")

       local parens = 0
       local finish = -1

       for j = start, str:len() do
          local char = str:sub( j, j )

          if char == "(" then
             parens = parens + 1

          elseif char == ")" then
             if parens > 0 then parens = parens - 1
             else finish = j - 1; break end

          elseif parens == 0 then
             -- We are not within a bracketed part of the string.  We can end here.
             if exprBreak[ char ] then
                finish = j - 1
                break
             end
          end
       end

       if finish == -1 then finish = str:len() end

       substring = str:sub( start + 1, finish )
       substring = substring:trim()

       str = format( "%s abs( %s ) %s", str:sub( 1, start - 1 ) or "", substring, str:sub( finish + 1, str:len() ) or "" )

       i = i + 1
       if i >= 100 then Hekili:Error( "Was unable to convert '@' to 'abs' in string [%s].", str ); break end
    end

    str = str:gsub( "%s%s", " " )

    return str
 end


 local leftBreak = {
    ["<"] = true,
    [">"] = true,
    ["="] = true,
    ["&"] = true,
    ["|"] = true,
    [","] = true,
    ["?"] = true,
    ["("] = true
}

local rightBreak = {
    ["<"] = true,
    [">"] = true,
    ["="] = true,
    ["&"] = true,
    ["|"] = true,
    [","] = true,
    ["?"] = true,
    ["+"] = true,
    ["-"] = true,
    ["%"] = true,
    ["*"] = true,
    ["/"] = true,
    [")"] = true
}

local function HandleDeprecatedOperators( str, opStr, prefix )
    for left, op, right in str:gmatch("(.+)(" .. opStr .. ")(.+)") do
        local leftLen, rightLen = left:len(), right:len()
        local val1, val2, len1, len2, b1, b2

        if left:sub(-1) == ")" then
            val1 = left:match("(%b())$")
            len1 = val1:len()
            val1 = val1:sub( 2, -2 )
        else
            -- We need to traverse the left side, backwards.
            local parens = 0
            local eos = -1

            for i = 1, leftLen do
                local char = left:sub(-i, -i)

                if char == ")" then
                    -- Grab the full bracketed pair and move on.
                    i = i + left:sub( 1, 1 + leftLen - i ):match( "(%b())$" ):len()
                elseif leftBreak[ char ] then
                    eos = i - 1
                    break
                end
            end

            if eos == -1 then
                val1 = left
                len1 = leftLen
            else
                val1 = left:sub( 1 + leftLen - eos, leftLen):trim()
                len1 = eos
            end
        end

        val1 = val1:trim()
        if not tonumber( val1 ) then val1 = format( "safenum(%s)", val1 ) end

        if right:sub(1, 1) == "(" then
            val2 = right:match("^(%b())")
            len2 = val2:len()
            val2 = val2:sub( 2, -2 )
        else
            local parens = 0
            local eos = -1

            for i = 1, right:len() do
                local char = right:sub(i, i)

                if char == "(" then
                    i = i + right:sub( i ):match( "^(%b())" ):len()
                elseif rightBreak[ char ] then
                    eos = i - 1
                    break
                end
            end

            if eos == -1 then
                val2 = right
                len2 = rightLen
            else
                val2 = right:sub(1, eos)
                len2 = eos
            end
        end

        val2 = val2:trim()
        if not tonumber( val2 ) then val2 = format( "safenum(%s)", val2 ) end

        local lhs = left:sub( 1, leftLen - len1 )
        if lhs:sub( -7 ) == "safenum" then
            lhs = lhs:sub( 1, -8 )
        elseif lhs:sub( -8 ) == "safebool" then
            lhs = lhs:sub( 1, -9 )
        end

        str = lhs .. prefix .. "(" .. val1 .. "," .. val2 .. ")" .. right:sub( 1 + len2 )
    end

    if str:find(opStr) then return scripts.HandleDeprecatedOperators( str, opStr, prefix ) end
    return str
end
scripts.HandleDeprecatedOperators = HandleDeprecatedOperators


-- A quote is no boundary: a quoted string (a choice setting's candidate, `settings.x='none'` or "none") stays literal.
local invalid = "([^a-zA-Z0-9_.['\"])"


local function extendExpression( str, expr, suffix )
    if str:find( expr ) then
        str = str:gsub( "^" .. expr .. invalid, expr .. "." .. suffix .. "%1" )
        str = str:gsub( invalid .. expr .. "$", "%1" .. expr .. "." .. suffix )
        str = str:gsub( "^" .. expr .. "$", expr .. "." .. suffix )
        str = str:gsub( invalid .. expr .. invalid, "%1" .. expr .. "." .. suffix .. "%2" )
    end

    return str
end


local function SimcWithResources( str )
    for k in pairs( GetResourceInfo() ) do
        if str:find( k ) then
            str = extendExpression( str, k, "current" )
        end
    end

    if str:find( "health" ) then
        str = extendExpression( str, "health", "current" )
    end

    if str:find( "rune" ) then
        str = extendExpression( str, "rune", "current" )
    end

    if str:find( "spell_targets" ) then
        str = extendExpression( str, "spell_targets", "any" )
    end

    if str:find( "gcd" ) then
        str = extendExpression( str, "gcd", "execute" )
    end

    return str
end


local function space_killer(s)
    return s:gsub("%s", "")
end

local function HandleLanguageIncompatibilities( str )
    -- Address equipped.number => equipped[number]
    str = str:gsub("%.(%d+)%.", "[%1].")
    str = str:gsub("equipped%.(%d+)", "equipped[%1]")
    str = str:gsub("main_hand%.(%d[a-z0-9_]+)", "main_hand['%1']")
    str = str:gsub("off_hand%.(%d[a-z0-9_]+)", "off_hand['%1']")
    str = str:gsub("lowest_vuln_within%.(%d+)", "lowest_vuln_within[%1]")
    str = str:gsub("%.in([^a-zA-Z0-9_])", "['in']%1" )
    str = str:gsub("%.in$", "['in']" )
    str = str:gsub("imps_spawned_during%.([^!=<>&|]+)", "imps_spawned_during['%1'] ")
    str = str:gsub("time_to_imps%.(%b()).remains", "time_to_imps[%1].remains")
    str = str:gsub("time_to_imps%.(%d+).remains", "time_to_imps[%1].remains")
    str = str:gsub("prev%.(%d+)", "prev[%1]")
    str = str:gsub("prev_gcd%.(%d+)", "prev_gcd[%1]")
    str = str:gsub("prev_off_gcd%.(%d+)", "prev_off_gcd[%1]")
    str = str:gsub("time_to_sht%.(%d+)", "time_to_sht[%1]")
    str = str:gsub("time_to_sht_plus%.(%d+)", "time_to_sht_plus[%1]")

    return str
end


-- Convert SimC syntax to Lua conditionals.
local function SimToLua( str, modifier )
    -- If no conditions were provided, function should return true.
    if not str or type( str ) == "number" then return str end

    local orig = str
    str = str:trim()

    if str == "" then return orig end

    -- Strip comments.
    str = str:gsub("^%-%-.-\n", "")

    -- Replace '!' with ' not '.
    str = str:gsub( "!=", "~=" )
    if str:find("!") then str = forgetMeNots( str ) end
    if str:find("@") then str = atToAbs( str ) end

    -- Replace '^' (simc XOR) with '~=' (functionally identical for booleans).
    if str:find("%^") then str = str:gsub("%^", "~=") end

    -- Replace '>?' and '<?' with max/min.
    if str:find("<%?") then str = HandleDeprecatedOperators( str, "<%?", "max" ) end
    if str:find(">%?") then str = HandleDeprecatedOperators( str, ">%?", "min" ) end

    str = SimcWithResources( str )

    -- Replace '&' with ' and '.
    str = str:gsub("&", " and ")

    -- Replace '|' with ' or '.
    str = str:gsub("||", " or "):gsub("|", " or ")

    if not modifier then
        -- Replace assignment '=' with comparison '=='
        str = str:gsub("([^=])=([^=])", "%1==%2" )

        -- Fix any conditional '==' that got impacted by previous.
        str = str:gsub("==+", "==")
        str = str:gsub(">=+", ">=")
        str = str:gsub("<=+", "<=")
        str = str:gsub("!=+", "~=")
        str = str:gsub("~=+", "~=")
    end

    -- Condense whitespace.
    str = str:gsub("%s%s", " ")

    -- Condense parenthetical spaces.
    str = str:gsub("[(][%s+]", "("):gsub("[%s+][)]", ")")

    -- Condense bracketed expressions.
    str = str:gsub("%b[]", space_killer)

    return HandleLanguageIncompatibilities( str )
end
scripts.SimToLua = SimToLua


-- CN25: the pure variables ({ [name] = scriptID }, scripts:MarkPure) of the pack whose line is being converted
local loadingPure


do
    -- Okay, this is the auto-recheck parser.

    -- Part I:  Split into parts.
    -- ex. combo_points<5&energy>=action.rake.cost&dot.rake.pmultiplier<2.1&buff.tigers_fury.up&(buff.bloodtalons.up|!talent.bloodtalons.enabled)&(!talent.incarnation.enabled|cooldown.incarnation.remains>18)&!buff.incarnation.up
    -- ...and break it into each compartmentalized expression:
    -- combo_points<5, energy>=action.rake.cost, dot.rake_multiplier<2.1.

    local boundaries = {
        ["&"] = true,
        ["|"] = true
    }

    function scripts:SplitExpr( str )
        local output = {}

        while( str:len() > 0 ) do
            local finish = str:len()
            local parens = 0

            for i = 1, str:len() do
                local char = str:sub( i, i )
                if char == "(" then parens = parens + 1
                elseif char == ")" then
                    if parens > 0 then parens = parens - 1 end
                elseif boundaries[ char ] and parens == 0 then
                    finish = i - 1
                    break
                end
            end

            local expr = str:sub( 1, finish )

            local meat = expr:match( "(%b())" )
            if meat then
                meat = meat:sub( 2, -2 )

                if meat:find( "[|&]" ) then
                    local subExpr = scripts:SplitExpr( meat )

                    for _, v in ipairs( subExpr ) do
                        table.insert( output, v )
                    end
                else
                    table.insert( output, expr )
                end
            else
                table.insert( output, expr )
            end
            str = str:sub( finish + 2, str:len() )
        end

        return output
    end

    local timely = {
        { "^(d?e?buff%.[a-z0-9_]+)%.down$"          , "%1.remains"                        },
        { "^(dot%.[a-z0-9_]+)%.down$"               , "%1.remains"                        },
        { "^!?(d?e?buff%.[a-z0-9_]+)%.up$"          , "%1.remains"                        },
        { "^!?(dot%.[a-z0-9_]+)%.up$"               , "%1.remains"                        },
        { "^!?(d?e?buff%.[a-z0-9_]+)%.react$"       , "%1.remains"                        },
        { "^!?(dot%.[a-z0-9_]+)%.react$"            , "%1.remains"                        },
        { "^!?(d?e?buff%.[a-z0-9_]+)%.stack$"       , "%1.remains"                        },
        { "^!?(d?e?buff%.[a-z0-9_]+)%.stack[<>]=?(.-)$", "0.01+%1.remains"                   },
        { "^!?(d?e?buff%.[a-z0-9_]+)%.ticking$"     , "%1.remains"                        },
        { "^!?(dot%.[a-z0-9_]+)%.ticking$"          , "%1.remains"                        },
        { "^!?(d?e?buff%.[a-z0-9_]+)%.remains$"     , "%1.remains"                        },
        { "^!?ticking"                              , "remains"                           },
        { "^!?remains$"                             , "remains"                           },
        { "^!?up$"                                  , "remains"                           },
        { "^!?down$"                                , "remains"                           },
        { "^!?refreshable$"                         , "time_to_refresh"                   },
        { "^!?buff%.([a-z0-9_]+)%.refreshable$"     , "buff.%1.time_to_refresh"           },
        { "^!?debuff%.([a-z0-9_]+)%.refreshable$"   , "debuff.%1.time_to_refresh"         },
        { "^!?dot%.([a-z0-9_]+)%.refreshable$"      , "debuff.%1.time_to_refresh"         },

        { "^time>=?(.-)$"                           , "0.01+%1-time"                      },
        { "^gcd.remains$"                           , "gcd.remains"                       },
        { "^gcd.remains<?=(.+)$"                    , "gcd.remains-%1"                    },
        { "^swing.([a-z_]+).remains$"               , "swing.%1.remains"                  },
        { "^(.-)%.deficit<=?(.-)$"                  , "0.01+%1.timeTo(%1.max-(%2))"       },
        { "^(.-)%.deficit>=?(.-)$"                  , "0.01+%1.timeTo(%1.max-(%2))"       },
        { "^target%.health%.pe?r?ce?n?t[<>=]+(.-)$" , "0.01+target['time_to_pct_' .. %1]" },

        { "^cooldown%.([a-z0-9_]+)%.ready$"                      , "cooldown.%1.remains"                      },
        { "^cooldown%.([a-z0-9_]+)%.up$"                         , "cooldown.%1.remains"                      },
        { "^!?cooldown%.([a-z0-9_]+)%.remains$"                  , "cooldown.%1.remains"                      },
        { "^!?cooldown%.([a-z0-9_]+)%.true_remains$"             , "cooldown.%1.true_remains"                 },
        { "^charges_fractional=(.-)$"                            , "(%1-charges_fractional)*recharge"         },
        { "^charges_fractional>=?(.-)$"                          , "0.01+(%1-charges_fractional)*recharge"    },
        { "^charges=(.-)$"                                       , "(%1-charges_fractional)*recharge"         },
        { "^charges>=?(.-)$"                                     , "0.01+(%1-charges_fractional)*recharge"    },
        { "^(cooldown%.[a-z0-9_]+)%.charges_fractional[>=]+(.-)$", "(%2-%1.charges_fractional)*%1.recharge"   },
        { "^(cooldown%.[a-z0-9_]+)%.charges>=?(.-)$"             , "(1+%2-%1.charges_fractional)*recharge"    },
        { "^(action%.[a-z0-9_]+)%.charges_fractional[>=]+(.-)$"  , "(%2-%1.charges_fractional)*%1.recharge"   },
        { "^(action%.[a-z0-9_]+)%.charges>=?(.-)$"               , "(1+%2-%1.charges_fractional)*%1.recharge" },
        { "^full_recharge_time[<>]=?(.-)$"                       , "0.01+full_recharge_time-%1"               },
        { "^!(action%.[a-z0-9]+)%.executing$"                    , "%1.execute_remains"                       },
        { "^!(action%.[a-z0-9]+)%.channeling$"                   , "%1.channel_remains"                       },
        { "^(.-time_to_die)<=?(.-)$"                             , "%1-%2"                                    },

        { "^(.-)%.time_to_(.-)<=?(.-)$", "%1.time_to_%2-%3" },

        { "^debuff%.festering_wound%.stack[>=]=?(.-)$" , "time_to_wounds(%1)" },
        { "^dot%.festering_wound%.stack[>=]=?(.-)$"    , "time_to_wounds(%1)" },
        { "^rune<=?(.-)$"                              , "rune.timeTo(%1)"    },
        { "^rune>=?(.-)$"                              , "rune.timeTo(1+%1)"  },
        { "^rune.current<=?(.-)$"                      , "rune.timeTo(%1)"    },
        { "^rune.current>=?(.-)$"                      , "rune.timeTo(1+%1)"  },

        { "^master_assassin_remains[<=]+(.-)$"      , "0.01+master_assassin_remains-(%1)"                              },
        { "^exsanguinated$"                         , "remains"                                                        }, -- Assassination
        { "^!?(debuff%.[a-z0-9_]+)%.exsanguinated$" , "%1.remains"                                                     }, -- Assassination
        { "^!?(dot%.[a-z0-9_]+)%.exsanguinated$"    , "%1.remains"                                                     }, -- Assassination
        { "^ss_buffed$"                             , "remains"                                                        }, -- Assassination
        { "^!?(debuff%.[a-z0-9_]+)%.ss_buffed$"     , "%1.remains"                                                     }, -- Assassination
        { "^!?(dot%.[a-z0-9_]+)%.ss_buffed$"        , "%1.remains"                                                     }, -- Assassination
        { "^dot%.([a-z0-9_]+).haste_pct_next_tick$" , "0.01+query_time+(dot.%1.last_tick+dot.%1.tick_time)-query_time" }, -- Assassination
        { "^!?stealthed.(.-)_remains<=?(.-)$"       , "stealthed.%1_remains-%2"                                        },
        { "^buff.envenom.max_stack_remains$"        , "buff.envenom.max_stack_remains"                                 },
        { "^buff.envenom.max_stack_remains<=?(.-)$" , "0.1+buff.envenom.max_stack_remains-(%1)"                        },
        { "^!?stealthed%.(normal)$"                 , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(vanish)$"                 , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(mantle)$"                 , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(subterfuge)$"             , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(shadow_dance)$"           , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(shadowmeld)$"             , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(sepsis)$"                 , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(improved_garrote)$"       , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(basic)$"                  , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(mantle)$"                 , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(rogue)$"                  , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(ambush)$"                 , "stealthed.%1_remains"                                          },
        { "^!?stealthed%.(all)$"                    , "stealthed.%1_remains"                                          },

        { "^!?death_and_decay.ticking$"             , "death_and_decay.remains"                                       }, -- DKs
        { "^!?drw.bp_ticking$"                      , "debuff.drw_blood_plague.remains" },

        { "^!?time_to_hpg$"           , "time_to_hpg"          }, -- Retribution Paladin
        { "^!?time_to_hpg[<=]=?(.-)$" , "time_to_hpg-%1"       }, -- Retribution Paladin
        { "^!?consecration.up"        , "consecration.remains" }, -- Prot        Paladin

        { "^!?contagion<=?(.-)"  , "contagion-%1"                 }, -- Affliction Warlock
        { "^time_to_imps%.(.+)$" , "time_to_imps[%1]"             }, -- Demo Warlock
        { "^!?diabolic_ritual$"  , "buff.diabolic_ritual.remains" }, -- Warlocks
        { "^!?demonic_art$"      , "buff.demonic_art.remains"     },
        
        { "^!?two_cast_imps>(.-)$" , "time_to_n_cast_imps_exceeds_y(2,1+(%1))" },
        { "^!?last_cast_imps>(.-)$", "time_to_n_cast_imps_exceeds_y(1,1+(%1))" },

        { "^active_bt_triggers$"       , "time_to_bt_triggers(0)"    }, -- Feral Druid w/ Bloodtalons.
        { "^active_bt_triggers<?=0$"   , "time_to_bt_triggers(0)"    }, -- Feral Druid w/ Bloodtalons.
        { "^active_bt_triggers<(%d+)$" , "time_to_bt_triggers(%1-1)" }, -- Feral Druid w/ Bloodtalons.

        { "^!?action%.([a-z0-9_]+)%.in_flight$"               , "action.%1.in_flight_remains"    }, -- Fire Mage, but others too, potentially.
        { "^!?action%.([a-z0-9_]+)%.in_flight_remains<=?(.-)$", "action.%1.in_flight_remains-%2" }, -- Fire Mage, but others too, potentially.

        { "^!?fiery_brand_dot_primary_remains$", "fiery_brand_dot_primary_remains" }, -- Vengeance
        { "^!?fiery_brand_dot_primary_ticking$", "fiery_brand_dot_primary_remains" }, -- Vengeance
        { "^!?elemental_equilibrium.active", "elemental_equilibrium.active_remains" }, -- Elemental Shaman

        { "^!?boar_charge.charges_remaining", "boar_charge.remains" }, -- Pack Leader Hunters

        { "^!?variable%.([a-z0-9_]+)$", "safenum(variable.%1)"                        },
        { "^!?variable%.([a-z0-9_]+)<=?(.-)$", "0.01+%2-safenum(variable.%1)"         },
        { "^raid_events%.([a-z0-9_]+)%.remains$", "raid_events.%1.remains"            },
        { "^raid_events%.([a-z0-9_]+)%.remains$<=?(.-)$", "raid_events.%1.remains-%2" },
        { "^!?raid_events%.([a-z0-9_]+)%.up$", "raid_events.%1.up"                    },
        { "^!?(pet%.[a-z0-9_]+)%.up$", "%1.remains"                                   },
        { "^!?(pet%.[a-z0-9_]+)%.active$", "%1.remains"                               },

        { "^(action%.[a-z0-9_]+)%.ready$", "%1.ready_time" }
    }


    -- Things that tick down.
    local decreases = {
        ["remains$"] = true,
        ["true_remains$"] = true,
        ["ticks_remain$"] = true,
        ["execute_remains$"] = true,
        ["channel_remains$"] = true,
        ["^time_to_hpg$"] = true,
        ["time_to_max$"] = true,
        ["remains_expected$"] = true,
        ["expiration_delay_remains$"] = true,
        -- ["time_to_%d+$"] = true,
        -- ["deficit$"] = true,
    }

    -- Clocks that tick down and wrap back to their period (the hands' swing clocks the class kits declare): the period.
    local wraps = {
        mainhand_remains = "mainhand_speed",
        offhand_remains = "offhand_speed",
        ranged_remains = "ranged_speed",
    }

    -- Things that tick up.
    local increases = {
        ["^time$"] = true,
        -- ["charges"] = true,
        -- ["charges_fractional"] = true,
    }

    local removals = {
        ["%.current"] = ""
    }

    local lessOrEqual = {
        -- ["<"] = true,
        ["<="] = true,
        ["="] = true,
        ["=="] = true,
    }

    local moreOrEqual = {
        -- [">"] = true,
        [">="] = true,
        ["="] = true,
        ["=="] = true,
    }

    local lhsTerms = {
        ["("] = true,
        ["&"] = true,
        ["|"] = true
     }

    local rhsTerms = {
        [")"] = true,
        ["&"] = true,
        ["|"] = true
    }


    -- Given an expression, can we assess whether it is time-based and progressing in a meaningful way?
    -- 1.  Cooldowns
    local function ConvertTimeComparison( expr, verbose )
        while expr:match( "^%b()$" ) do
            expr = expr:sub( 2, -2 )
        end

        -- CN25: a pure variable's read has no time of its own: its value's are the line's (State.lua recurseRechecks)
        local pure = loadingPure and expr:match( "^!?variable%.([a-z0-9_]+)$" )
        if pure and loadingPure[ pure ] then return false, nil end

        local orig = expr

        for k, v in pairs( removals ) do
            expr = expr:gsub( k, v )
        end

        local lhs, comp, rhs = expr:match( "^(.-)([<>=~?]+)(.-)$" )

        -- Finding that SplitExpr is falling short occasionally; need to trim lhs and rhs to the most appropriate balanced pair.
        local brace_depth = 0

        if lhs then
            for i = lhs:len(), 1, -1 do
                local char = lhs:sub( i, i )
                if char == ")" then
                    brace_depth = brace_depth + 1
                elseif char == "(" then
                    brace_depth = brace_depth - 1
                end

                if brace_depth < 0 and lhsTerms[ char ] then
                    lhs = lhs:sub( i + 1, lhs:len() )
                    break
                end
            end
        end

        if rhs then
            brace_depth = 0
            for i = 1, rhs:len() do
                local char = rhs:sub( i, i )

                if char == "(" then
                    brace_depth = brace_depth + 1
                elseif char == ")" then
                    brace_depth = brace_depth - 1
                end

                if brace_depth < 0 and rhsTerms[ char ] then
                    rhs = rhs:sub( 1, i - 1  )
                    break
                end
            end
        end

        if comp and comp:match( "?" ) then
            comp = nil
        end

        if lhs and comp and rhs then
            -- We are looking at a mathematic comparison.
            -- Forever R6: a hand's swing clock counts down and wraps back to its speed at the swing, so `>`/`>=` turns
            -- true just past the wrap (EmulateSyntax may have wrapped the term in safenum).
            -- shortcut: 0.01 past the wrap the clock reads speed - 0.01, so `clock>speed-x` with x <= 0.01 is still
            -- false there and its forecast is missed; no pack compares that close. Upgrade if one does.
            -- shortcut: the clock is recognised on the left only (`speed-x<clock` falls to the generic fallback); the
            -- translator writes it there (tools/wowsims/apl.lua rule 10). Upgrade when a pack puts it right.
            local clock = lhs:match( "^safenum%(([%w_]+)%)$" ) or lhs
            if wraps[ clock ] then
                if comp == ">" or comp == ">=" then
                    return true, lhs .. " + 0.01"
                end
                -- R61: `<`/`<=` a fixed x (a since-swing guard, `clock<=speed-g`) holds until the wrap, then again once
                -- the clock falls from its speed back to x: the time to x now, and the wrap's time plus (speed - x),
                -- each 0.01 past its crossing like the wrap's. Two moving clocks (`clock<other_remains`) keep one time.
                if comp == "<" or comp == "<=" then
                    local now = "0.01 + " .. lhs .. " - (" .. rhs .. ")"
                    if rhs:find( "remains", 1, true ) then return true, now end
                    return true, now .. ", 0.01 + " .. lhs .. " + " .. wraps[ clock ] .. " - (" .. rhs .. ")"
                end
            end

            for key in pairs( decreases ) do
                if lhs:match( key ) then
                    if comp == "<" then
                        return true, "(" .. lhs .. " + 0.01) - (" .. rhs .. ")"
                    elseif lessOrEqual[ comp ] then
                        return true, lhs .. " - " .. rhs
                    end
                end
            end

            for key in pairs( increases ) do
                if lhs:match( key ) then
                    if comp == ">" then
                        return true, "(" .. rhs .. " + 0.01) - (" .. lhs .. ")"
                    elseif moreOrEqual[ comp ] then
                        return true, rhs .. " - " .. lhs
                    end
                end
            end

            -- resources also tick up (usually, anyway)
            for key in pairs( GetResourceInfo() ) do
                if lhs == key then
                    if comp == ">" then
                        return true, "0.01 + " .. lhs .. ".timeTo( " .. rhs .. " ), " .. lhs .. ".timeTo( 1 + ( " .. rhs .. " ) )"
                    elseif moreOrEqual[ comp ] then
                        return true, lhs .. ".timeTo( " .. rhs .. " )"
                    end
                end

                if rhs == key then
                    if comp == "<" then
                        return true, "0.01 + " .. rhs .. ".timeTo( " .. lhs .. " ), " .. rhs .. ".timeTo( 1 + ( " .. lhs .. " ) )"
                    elseif lessOrEqual[ comp ] then
                        return true, rhs .. ".timeTo( " .. lhs .. " )"
                    end
                end

                -- the floor's reads (border batch 2): `energy.lo>=N`, `mana.pct_lo<=N` reach on the floor's stream
                if lhs == ( key .. ".lo" ) then
                    if comp == ">" then
                        return true, "0.01 + " .. key .. ".timeToLo( " .. rhs .. " ), " .. key .. ".timeToLo( 1 + ( " .. rhs .. " ) )"
                    elseif moreOrEqual[ comp ] then
                        return true, key .. ".timeToLo( " .. rhs .. " )"
                    end
                end

                if rhs == ( key .. ".lo" ) then
                    if comp == "<" then
                        return true, "0.01 + " .. key .. ".timeToLo( " .. lhs .. " ), " .. key .. ".timeToLo( 1 + ( " .. lhs .. " ) )"
                    elseif lessOrEqual[ comp ] then
                        return true, key .. ".timeToLo( " .. lhs .. " )"
                    end
                end

                if lhs == ( key .. ".pct_lo" ) then
                    if comp == ">" then
                        return true, "0.01 + " .. key .. ".timeToLo( " .. key .. ".max * ( " .. rhs .. " / 100 ) ), " .. key .. ".timeToLo( 1 + " .. key .. ".max * ( ( " .. rhs .. " ) / 100 ) )"
                    elseif moreOrEqual[ comp ] then
                        return true, key .. ".timeToLo( " .. key .. ".max * ( " .. rhs .. " / 100 ) ), " .. key .. ".timeToLo( 1 + " .. key .. ".max * ( ( " .. rhs .. " ) / 100 ) )"
                    end
                end

                if rhs == ( key .. ".pct_lo" ) then
                    if comp == "<" then
                        return true, "0.01 + " .. key .. ".timeToLo( " .. key .. ".max * ( " .. lhs .. " / 100 ) ), " .. key .. ".timeToLo( 1 + " .. key .. ".max * ( ( " .. lhs .. " ) / 100 ) )"
                    elseif lessOrEqual[ comp ] then
                        return true, key .. ".timeToLo( " .. key .. ".max * ( " .. lhs .. " / 100 ) ), " .. key .. ".timeToLo( 1 + " .. key .. ".max * ( ( " .. lhs .. " ) / 100 ) )"
                    end
                end

                if lhs == ( key .. ".percent" ) or lhs == ( key .. ".pct" ) then
                    if comp == ">" then
                        return true, "0.01 + " .. key .. ".timeTo( " .. key .. ".max * ( " .. rhs .. " / 100 ) ), " .. key .. ".timeTo( 1 + " .. key .. ".max * ( ( " .. rhs .. " ) / 100 ) )"
                    elseif moreOrEqual[ comp ] then
                        return true, key .. ".timeTo( " .. key .. ".max * ( " .. rhs .. " / 100 ) ), " .. key .. ".timeTo( 1 + " .. key .. ".max * ( ( " .. rhs .. " ) / 100 ) )"
                    end
                end

                if rhs == ( key .. ".percent" ) or rhs == ( key .. ".pct" ) then
                    if comp == "<" then
                        return true, "0.01 + " .. key .. ".timeTo( " .. key .. ".max * ( " .. lhs .. " / 100 ) ), " .. key .. ".timeTo( 1 + " .. key .. ".max * ( ( " .. lhs .. " ) / 100 ) )"
                    elseif lessOrEqual[ comp ] then
                        return true, key .. ".timeTo( " .. key .. ".max * ( " .. lhs .. " / 100 ) ), " .. key .. ".timeTo( 1 + " .. key .. ".max * ( ( " .. lhs .. " ) / 100 ) )"
                    end
                end
            end

            if lhs == "rune" then
                if comp == ">" then
                    return true, "0.01 + rune.timeTo( " .. rhs .. " ), rune.timeTo( 1 + ( " .. rhs .. " ) )"
                elseif moreOrEqual[ comp ] then
                    return true, "rune.timeTo( " .. rhs .. " )"
                end
            end

            if rhs == "rune" then
                if comp == "<" then
                    return true, "0.01 + rune.timeTo( " .. lhs .. " ), rune.timeTo( 1 + ( " .. lhs .. " ) )"
                elseif lessOrEqual[ comp ] then
                    return true, "rune.timeTo( " .. lhs .. " )"
                end
            end
        end

        -- If we didn't convert a resource.current to resource.timeTo then let's revert our string.
        expr = orig

        for i, swap in ipairs( timely ) do
            if expr:match( swap[1] ) then
                return true, expr:gsub( swap[1], swap[2]), swap[1]
            end
        end

        if comp and comp:match( "[<>]=?" ) then
            return true, "0.01 + " .. lhs .. " - " .. rhs, "fallback"
        end

        return false, nil
    end

    scripts.CTC = ConvertTimeComparison

    function scripts:RecheckExpr( expr )
        return ConvertTimeComparison( expr )
    end

    -- parts (optional): filled with each distinct time in order, and [ part ] = true (the times are a set: a repeat
    -- adds nothing, so each is kept once)
    function scripts:BuildRecheck( conditions, parts )
        if type( conditions ) ~= "string" then return end

        local recheck
        parts = parts or {}

        conditions = conditions:gsub( " +", "" )
        conditions = self:EmulateSyntax( conditions, true )
        local exprs = self:SplitExpr( conditions )

        if #exprs > 0 then
            for i, expr in ipairs( exprs ) do
                local converted, calc, why = ConvertTimeComparison( expr )

                if converted then
                    -- A conversion may return several times joined by ", " (R61); the spaces were stripped from the
                    -- conditions above, so a ", " is only ever that join. Each time is converted on its own.
                    for part in ( calc .. ", " ):gmatch( "(.-), " ) do
                        part = SimToLua( part )
                        part = self:EmulateSyntax( part, true )

                        local rslt, msg = Hekili:Loadstring( "return " .. part )
                        if not rslt then
                            Hekili:Debug( "Recheck failed to loadstring: %s", msg )
                        elseif not parts[ part ] then
                            parts[ part ], parts[ #parts + 1 ] = true, part
                            recheck = ( recheck and ( recheck .. ", " ) or "" ) .. part
                        end
                    end
                end
            end
        end

        return recheck
    end


    local ops = {
        ["+"] = true,
        ["-"] = true,
        ["*"] = true,
        ["/"] = true,
        ["%"] = true,
        ["|"] = true,
        ["&"] = true,
        ["<"] = true,
        [">"] = true,
        ["?"] = true,
        ["="] = true,
        ["~"] = true,
        ["!"] = true,
        ["!="] = true,
        ["~="] = true,
        ["@"] = true,
        [","] = true
     }

    local math_ops = {
        ["+"] = true,
        ["-"] = true,
        ["*"] = true,
        ["/"] = true,
        ["%"] = true,
        ["<"] = true,
        [">"] = true,
        ["<="] = true,
        [">="] = true,
        [">?"] = true,
        ["<?"] = true,
    }

    local equality = {
        ["="] = true,
        ["!="] = true,
        ["~="] = true,
    }

    local comp_ops = {
        ["<"] = true,
        [">"] = true,
        ["?"] = true,
    }

    local bool_ops = {
        ["|"] = true,
        ["&"] = true,
        ["!"] = true,
    }

    local funcs = {
        ["floor"] = true,
        ["ceil"] = true,
        ["max"] = true,
        ["min"] = true
    }


    -- This is hideous.

    local esDepth = 0
    local esString

    local tree = {}

    function scripts:EmulateSyntax( p, numeric )
        if not p or type( p ) ~= "string" then return p end

        insert( tree, p )

        if esDepth == 0 then
            esString = p
        end
        esDepth = esDepth + 1

        local results = {}

        local i, maxlen = 1, p:len()
        local depth = 0

        local bracketed = p:match("(%b())" ) == p
        if bracketed then
            p = p:sub( 2, p:len() - 1 )
        end

        local ands = p:find( " and " )
        local ors = p:find( " or " )
        local nots = p:find( " not " )
        local abss = p:find( " abs " )

        if ands then p = p:gsub( " and ", "&" ) end
        if ors then p = p:gsub( " or ", "|" ) end
        if nots then p = p:gsub( " not ", "!" ) end
        if abss then p = p:gsub( " abs ", "@" ) end

        p = p:gsub( "([!%|&%-%+%*=%%/<>%?%~@]+) +", "%1" )
        p = p:gsub( " +([!%|&%-%+%*=%%/<>%?%~@]+)", "%1" )

        local orig = p

        while ( i <= maxlen ) do
            local c = p:sub( i, i )

            if c == " " or c == "," then -- do nothing
            elseif c == "(" then depth = depth + 1
            elseif c == ")" and depth > 0 then
                depth = depth - 1

                if depth == 0 then
                    local expr = p:sub( 1, i )

                    table.insert( results, {
                        s = expr:trim(),
                        t = "expr"
                    } )

                    if expr:find( "[&%|%-%+/%%%*]" ) ~= nil then results[#results].r = true end

                    p = p:sub( i + 1 )
                    i = 0
                    depth = 0
                    maxlen = p:len()
                end
            elseif depth == 0 and ops[c] then
                if i > 1 then
                    local expr = p:sub( 1, i - 1 )

                    table.insert( results, {
                        s = expr:trim(),
                        t = "expr"
                    } )

                    if expr:find( "[&$|$-$+/$%%*]" ) ~= nil then results[#results].r = true end
                end

                c = p:sub( i ):match( "^([&%|%-%+*%%/><!%?=%~@][&%|%-%+*/><%?=%~]?)" )

                table.insert( results, {
                    s = c,
                    t = "op",
                    a = c:trim() --sub(1,1)
                } )

                p = p:sub( i + c:len() )
                i = 0
                depth = 0
                maxlen = p:len()
            end

            i = i + 1
        end

        p = p:trim()

        if p:len() > 0 then
            table.insert( results, {
                    s = p:trim(),
                    t = "expr",
                    l = true
            } )

            if p:find( "[!&%|%-%+/%%%*@]" ) ~= nil then results[#results].r = true end
        end

        local output = ""

        -- So at this point, we've broken our string into all of its components.  Now let's iterate through and fix it up.
        i = 1

        while( i <= #results ) do
            local prev, piece, next = i > 1 and results[i-1] or nil, results[i], i < #results and results[i+1] or nil
            local trimmed_prefix

            -- If we get a math op (*) followed by a not (!) followed by an expression, we want to safely wrap up the !expr in safenum().
            if prev and prev.t == "op" and math_ops[ prev.a ] and piece.t == "op" and piece.a == "!" and next and next.t == "expr" then
                table.remove( results, i )
                piece = results[ i ]
                next = results[ i + 1 ]
                piece.s = "(!" .. piece.s .. ")"
            elseif piece.t == "expr" and piece.s:match( "^%s*[a-z0-9_]+%s*%(" ) then
                trimmed_prefix = piece.s:match( "^%s*([a-z0-9_]+)%s*%(" )
                if trimmed_prefix == "max" or trimmed_prefix == "min" then
                    piece.s = piece.s:gsub( "%s*", "" )
                    trimmed_prefix = nil
                else
                    piece.s = piece.s:gsub( "^%s*" .. trimmed_prefix .. "%s*", "" )
                end
            end

            if piece and piece.t == "expr" then
                if piece.r then
                    if piece.s == orig then
                        if bracketed then orig = "(" .. orig .. ")" end
                        if ands then orig = orig:gsub( "&", " and " ) end
                        if ors then orig = orig:gsub( "|", " or " ) end
                        if nots then orig = orig:gsub( "!", " not " ) end
                        if abss then orig = orig:gsub( "@", " abs " ) end

                        esDepth = esDepth - 1
                        table.remove( tree )

                        return orig
                    end

                    local isNumber = numeric and prev == nil and next == nil or prev and math_ops[ prev.a ] or next and math_ops[ next.a ]
                    piece.s = scripts:EmulateSyntax( piece.s, isNumber, squawk )
                end

                if ( prev and prev.t == "op" and math_ops[ prev.a ] and not equality[ prev.a ] ) or ( next and next.t == "op" and math_ops[ next.a ] and not equality[ next.a ] ) then
                    -- This expression is getting mathed.
                    -- Lets see what it returns and wrap it in btoi if it is a boolean expr.
                    if piece.s:find("^variable%.") then
                        -- Let's wrap the variable just to be sure.
                        if piece.s:sub(1, 1) == "(" then piece.s = "safenum" .. piece.s
                        else piece.s = "safenum(" .. piece.s .. ")" end
                    else
                        local func, warn = Hekili:Loadstring( "return " .. ( SimToLua( piece.s ) or "" ) )
                        if func then
                            setfenv( func, state )
                            state:SetDefaultVariable( 1 )
                            local pass, val = pcall( func )
                            state:SetDefaultVariable( 0 )

                            if not pass and not piece.s:match("variable") then
                                local safepiece = piece.s:gsub( "%%", "%%%%" )
                                Hekili:Error( "Unable to compile '" .. safepiece:gsub("%%", "%%%%") .. "' - " .. val .. " (pcall-n)\n\nFrom: " .. esString:gsub( "%%", "%%%%" ) )
                            else
                                if trimmed_prefix ~= "safenum" and ( val == nil or type( val ) ~= "number" ) then piece.s = "safenum(" .. piece.s .. ")" end
                            end
                        else
                            local treetoString
                            for i = #tree, 1, -1 do
                                local elem = tree[ i ]
                                if treeToString then treeToString = format( "%s\n[%d] %s", treeToString, i, elem )
                                else treeToString = format( "[%d] %s", i, elem ) end
                            end
                            Hekili:Error( "Unable to compile '" .. ( piece.s ):gsub("%%","%%%%") .. "' - " .. warn .. " (loadstring-n)\n\nFrom: " .. treeToString )
                        end
                    end
                    piece.r = nil

                elseif not numeric and ( not prev or ( prev.t == "op" and not math_ops[ prev.a ] and not equality[ prev.a ] ) ) and ( not next or ( next.t == "op" and not math_ops[ next.a ] and not equality[ next.a ] ) ) then
                    -- This expression is not having math operations performed on it.
                    -- Let's make sure it's a boolean.
                    if piece.s:find("^variable") then
                        if piece.s:sub(1, 1) == "(" then piece.s = "safebool" .. piece.s
                        else piece.s = "safebool(" .. piece.s .. ")" end
                    else
                        local func, warn = Hekili:Loadstring( "return " .. ( SimToLua( piece.s ) or "" ) )
                        if func then
                            setfenv( func, state )

                            state:SetDefaultVariable( 1 )
                            local pass, val = pcall( func )
                            state:SetDefaultVariable( 0 )

                            if not pass and not piece.s:match("variable") then
                                local safepiece = piece.s:gsub( "%%", "%%%%" )
                                Hekili:Error( "Unable to compile '" .. safepiece:gsub("%%", "%%%%") .. "' - " .. val .. " (pcall-b)\nFrom: " .. esString:gsub( "%%", "%%%%" ) )
                            else
                                if trimmed_prefix ~= "safebool" and ( val == nil or type( val ) == "number" ) then
                                    piece.s = "safebool(" .. piece.s .. ")"
                                end
                            end
                        else
                            Hekili:Error( "Unable to compile '" .. ( piece.s ):gsub("%%","%%%%") .. "' - " .. warn .. " (loadstring-b)." )
                        end
                    end
                    piece.r = nil
                end
            end

            if trimmed_prefix then
                piece.s = trimmed_prefix .. piece.s
            end

            output = output .. piece.s
            i = i + 1
        end

        if bracketed then output = "(" .. output .. ")" end
        if ands then output = output:gsub( "&", " and " ) end
        if ors then output = output:gsub( "|", " or " ) end
        if nots then output = output:gsub( "!", " not " ) end
        if abss then output = output:gsub( "@", " abs" ) end

        output = output:gsub( "!safenum(%b())", "safenum(!%1)" )
        output = output:gsub( "@safebool", "@safenum" )
        output = output:gsub( "!%(%s*(%b())%s*%)", "!%1" )
        output = output:gsub( "%(%s*(%b())%s*%)", "%1" )

        esDepth = esDepth - 1
        table.remove( tree )
        return output
    end
end


local function stripScript( str, thorough )
  if not str then return 'true' end
  if type( str ) == 'number' then return str end

  -- Remove the 'return ' that was added during conversion.
  str = str:gsub("^return ", "")

  -- Remove min/max/safenum/safebool/abs.
  str = str:gsub( "abs(%b())", "%1" ):gsub( "min(%b())", "%1" ):gsub( "max(%b())", "%1" ):gsub( "safebool(%b())", "%1" ):gsub( "safenum(%b())", "%1" )

  -- Remove comments.
  str = str:gsub("%-%-.-\n", "")

  -- Remove conjunctions.
  str = str:gsub("[%s-]and[%s-]", " "):gsub("[%s-]or[%s-]", " "):gsub("%(-%s-not[%s-]", " ")

  if not thorough then
    -- Collapse whitespace around comparison operators.
    str = str:gsub("[%s-]==[%s-]", "=="):gsub("[%s-]>=[%s-]", ">="):gsub("[%s-]<=[%s-]", "<="):gsub("[%s-]~=[%s-]", "~="):gsub("[%s-]<[%s-]", "<"):gsub("[%s-]>[%s-]", ">")
  else
    -- Strip operators and parentheses.
    str = str:gsub("[=+]", " "):gsub("[><~]%??", " "):gsub("[%*//%-%+]", " "):gsub("[%(%)]", " ")
  end

  str = str:gsub( "([%a%w_])%.(%d+)", "%1[%2]" )
  str = str:gsub( "%.in([ %.])", "['in']%1")

  -- Collapse the rest of the whitespace.
  str = str:gsub("[%s+]", " ")

  return ( str )
end

scripts.stripScript = stripScript


do
    local ignore = {
        min = 1,
        max = 1
    }

    function scripts:StoreValues( tbl, node, mod )
        wipe( tbl )

        if type( node ) == 'string' then node = self.DB[ node ] end
        if not node then return end

        local elems
        if mod then elems = node.ModElements[ mod ]
        else elems = node.Elements end

        if not elems then return end

        for k, v in pairs( elems ) do
            if not ignore[ k ] then
                local s, r = pcall( v )

                if s then tbl[ k ] = r
                elseif type( r ) == 'string' then tbl[ k ] = r:match( "lua:(%d+: .*)" ) or r end
                if tbl[ k ] == nil then tbl[ k ] = 'nil' end
            end
        end
    end
end


function scripts:StoreReadyValues( tbl, node )
    self:StoreValues( tbl, node, "ready" )
end


function scripts:GetScript( scriptID )
    return self.DB[ scriptID ]
end


local function GetScriptElements( script )
    if type( script ) == 'number' then return end

    local e, c = {}, stripScript( script, true )

    for s in c:gmatch( "[^ ,]+" ) do
        while s:match("^(%b())$" ) do s = s:sub( 2, -2 ) end
        if not e[ s ] and not tonumber( s ) then
            local ef = Hekili:Loadstring( "return ".. s )
            if ef then
                setfenv( ef, state )
                local success, v = pcall( ef )

                if success then
                    e[ s ] = ef
                end
            end
        end
    end

    return e
end
scripts.GetScriptElements = GetScriptElements


-- newModifiers, key is the name of the element, value is whether to babyproof it or not.
local newModifiers = {
    chain = 'bool',
    early_chain_if = 'bool',
    interrupt = 'bool',
    interrupt_global = 'bool',
    interrupt_if = 'bool',
    interrupt_immediate = 'bool',
    max_energy = 'bool',
    moving = 'bool',
    only_cwc = 'bool',
    strict = 'bool',
    target_if = 'bool',
    use_off_gcd = 'bool',
    use_while_casting = 'bool',
    wait = 'bool',

    -- Not necessarily a number, but not baby-proofed.
    cycle_targets = 'raw',
    default = 'raw',
    for_next = 'raw',
    extra_amount = 'raw',
    line_cd = 'raw',
    max_cycle_targets = 'raw',
    other_target = 'raw', -- 1: for another target only (a forced cycle, option D)
    sec = 'raw',
    value = 'raw',
    value_else = 'raw',
    strict_if = 'raw',

    sync = 'string', -- should be an ability's name.
    action_name = 'string',
    buff_name = 'string',
    list_name = 'string',
    op = 'string',
    var_name = 'string',

    -- the rotation window lines: open_window/close_window,name=<w> (windows design v6 ruling 21: name= and if= only)
    window_name = 'string',

    -- shown with the pick (Core's markPick): text on its icon, and an icon a display may draw instead, each only while
    -- its _if holds. 'text' is the line's value verbatim: no SimC translation, so a texture path keeps its backslashes.
    label = 'text', -- a modifier type, not player text -- l10n: verbatim
    label_if = 'bool',
    icon = 'text',
    icon_if = 'bool',
}


-- A 'text' modifier's Lua source: the value verbatim, except icon=, always a texture file ID as a number literal
-- (SetTexture( "136006" ) would look up a path): a bare number as given (the client cannot tell a missing one), a path
-- resolved here once; a path the client lacks (or answers secret) gives the line no icon override (nil) and one
-- warning naming the line.
local function textSource( m, v, header, action )
    if m ~= 'icon' then return format( "%q", tostring( v ) ) end
    local id = tonumber( v ) or GetFileIDFromPath( tostring( v ) )
    if not issecretvalue( id ) and id then return tostring( id ) end -- secrecy first: no boolean test on a secret
    Hekili:Error( "Priority line %s (%s): icon=%s is not a texture file; the line's icon is not overridden.", tostring( header ), tostring( action ), tostring( v ) )
end


local valueModifiers = {
    sec = true,
    value = true,
    value_else = true,
    line_cd = true,
    max_cycle_targets = true,
    strict_if = true
}


local isString = {
    op = true,
}


local debugArgTemplate = [[%s
local arg%d = debugformat( %s )]]

local debugPrintTemplate = [[-- %s %s
local prev_action = this_action
this_action = "%s"
%s
this_action = prev_action
return format( "%s", %s )]]

local function generateDebugPrint( node, condition, header, isRecheck )
    local cleanPrint = SimcWithResources( condition:trim() ):gsub( "%%", "%%%%" ):gsub( "\"", "'" )

    local seen = {}
    local argn = 0
    local formatArgs, generateDebug, debugPrint = nil, "", nil

    -- A quoted literal (a choice setting's candidate, `settings.x='none'`) holds no terms: tokenize without them.
    for token in ( cleanPrint:gsub( "'[^']*'", "" ) ):gmatch( "[a-zA-Z][A-Za-z0-9_%.]+" ) do
        if not seen[ token ] then
            argn = argn + 1
            seen[ token ] = "arg" .. argn

            generateDebug = format( debugArgTemplate, generateDebug, argn, token )
        end

        if not formatArgs then
            formatArgs = "arg1"
        else
            formatArgs = format( "%s, %s", formatArgs, seen[ token ] )
        end
    end

    if argn > 0 then
        local replacements = {}

        for k, v in pairs( seen ) do
            insert( replacements, { k, "{" .. v .. "}" } )
        end

        sort( replacements, function( a, b ) return a[1]:len() > b[1]:len() end )

        for _, replace in ipairs( replacements ) do
            cleanPrint = cleanPrint:gsub( replace[1], replace[2] )
        end

        for _, replace in ipairs( replacements ) do
            cleanPrint = cleanPrint:gsub( replace[2], replace[1] .. "[%%s]" )
        end

        generateDebug = format( debugPrintTemplate, header, isRecheck and "recheck debug" or "condition debug", node.action or "wait", generateDebug, cleanPrint, formatArgs )
        generateDebug = HandleLanguageIncompatibilities( generateDebug )
        debugPrint, formatArgs = Hekili:Loadstring( generateDebug )

        if formatArgs then
            Hekili:Error( "Unable to generate debug print for " .. header .. ": " .. formatArgs:gsub( "%%", "%%%%" ) .. "\n" .. generateDebug:gsub( "%%", "%%%%" ) )
            return
        end

        return generateDebug, setfenv( debugPrint, state )
    end
end


-- Need to convert all the appropriate scripts and store them safely...
local function ConvertScript( node, hasModifiers, header )
    local previousScript = state.scriptID
    state.scriptID = header

    state.this_action = node.action
    state.this_list = header:match( "^(.-):" ) or "default"

    local t = node.criteria and node.criteria ~= "" and node.criteria
    local clean = SimToLua( t )

    t = scripts:EmulateSyntax( t )
    local tPreSim = t

    t = SimToLua( t )

    local sf, e

    if t then sf, e = Hekili:Loadstring( "-- " .. header .. "\nreturn safebool( " .. t .. " )" ) end
    if sf then setfenv( sf, state ) end

    if sf and not e then
        state:SetDefaultVariable( 1 )
        local success, msg = pcall( sf )
        if not success then e = msg end
        state:SetDefaultVariable( 0 )
    end
    if e then e = e:match( ":(%d+: .*)" ) or e end

    local se = clean and GetScriptElements( clean )

    local varPool
    local generateDebug, debugPrint

    if se then
        local hasElements = false

        for k, v in pairs( se ) do
            hasElements = true

            if k:sub( 1, 8 ) == "variable" then
                varPool = varPool or {}
                table.insert( varPool, k:sub( 10 ) )
            end
        end

        if hasElements then
            generateDebug, debugPrint = generateDebugPrint( node, node.criteria, header )
        end
    end

    -- autorecheck...
    local rs, rc, erc, rEle, rParts
    local recheckDebug, recheckPrint

    local hasCriteria = node.criteria and node.criteria ~= ""
    local hasValue = node.value and node.value ~= ""
    local hasValueElse = node.value_else and node.value_else ~= ""

    if hasCriteria or hasValue or hasValueElse then
        rParts = {}
        if node.action == "variable" then
            rs = format( "%s | %s | %s", hasCriteria and node.criteria or "1", hasValue and node.value or "1", hasValueElse and node.value_else or "1" )
            rs = scripts:BuildRecheck( rs, rParts )
        else
            rs = scripts:BuildRecheck( node.criteria, rParts )
        end

        if rs then
            rc, erc = Hekili:Loadstring( "-- " .. header .. " recheck\nreturn " .. rs )
            if rc then setfenv( rc, state ) end

            rEle = GetScriptElements( rs )

            if type( rc ) ~= "function" then
                Hekili:Error( "Recheck function for " .. clean .. " ( " .. ( rs or "nil" ) .. ") was unsuccessful somehow." )
                rc = nil
            end
        end
    end

    local output = scripts.DB[ header ]
    if output then wipe( output )
    else output = {} end

    local specialMods = ""

    if output.Modifiers then wipe( output.Modifiers ) end
    local modifiers = output.Modifiers or {}

    if output.ModElements then wipe( output.ModElements ) end
    local modElements = output.ModElements or {}

    if output.ModEmulates then wipe( output.ModEmulates ) end
    local modEmulates = output.ModEmulates or {}

    if output.ModSimC then wipe( output.ModSimC ) end
    local modSimC = output.ModSimC or {}

    output.Conditions = sf
    output.Error = e
    output.Elements = se
    output.Print = debugPrint
    output.Debug = generateDebug

    output.Recheck = rc
    output.RecheckScript = rs
    output.RecheckParts = rParts -- its distinct times (State.lua joins a line's with those of the variables it reads)
    output.RecheckError = erc
    output.RecheckElements = rEle
    output.RecheckPrint = recheckPrint
    output.RecheckDebug = recheckDebug

    if hasModifiers then
        for m, value in pairs( newModifiers ) do
            local text = node[ m ] and value == 'text' and textSource( m, node[ m ], header, node.action )
            if node[ m ] and ( value ~= 'text' or text ) then
                local emulated
                local o = text or SimToLua( node[ m ] )

                specialMods = specialMods .. " - " .. m .. " : " .. o

                local sf, e

                if value == 'bool' then
                    emulated = SimToLua( scripts:EmulateSyntax( node[ m ] ) )

                elseif value == 'raw' then
                    emulated = node[ m ] ~= "" and node[ m ]
                    emulated = SimToLua( scripts:EmulateSyntax( emulated, true ) )
                elseif value == 'text' then
                    emulated = o
                else -- string
                    o = "'" .. o .. "'"
                    emulated = o
                end

                if emulated then
                    sf, e = Hekili:Loadstring( "return " .. emulated )
                end

                if sf then
                    setfenv( sf, state )
                    modifiers[ m ] = sf
                    modElements[ m ] = value ~= 'text' and GetScriptElements( o ) or nil

                    if modElements[ m ] then
                        for k, v in pairs( modElements[ m ] ) do
                            if k:sub( 1, 8 ) == "variable" then
                                varPool = varPool or {}
                                table.insert( varPool, k:sub( 10 ) )
                            end
                        end
                    end

                    modEmulates[ m ] = emulated
                    if type( node[ m ] ) == 'string' then modSimC[ m ] = SimcWithResources( node[ m ]:trim() ) end
                else
                    modifiers[ m ] = nil
                    modifiers[ "error:" .. m ] = e .. "\n - " .. emulated
                    Hekili:Error( format( "Error in %s modifier %s: %s\n\n - %s", header, m, e, emulated ) )
                end
            end
        end
    end

    output.Modifiers = hasModifiers and modifiers
    output.ModElements = hasModifiers and modElements
    output.ModEmulates = hasModifiers and modEmulates
    output.ModSimC = hasModifiers and modSimC
    output.SpecialMods = specialMods

    output.Variables = varPool

    output.Lua = clean and clean:trim() or nil
    output.Emulated = t and t:trim() or nil
    output.EmuPreSim = tPreSim and tPreSim:trim() or nil
    output.SimC = node.criteria and SimcWithResources( node.criteria:trim() ) or nil
    output.ID = header

    state.scriptID = previousScript
    return output
end
scripts.ConvertScript = ConvertScript


function scripts:CheckScript( scriptID, action, elem, default )
    local prev_action = state.this_action
    if action then
        state.this_action = action
    end

    local script = self.DB[ scriptID ]

    if not script then
        state.this_action = prev_action
        return false
    end

    if not elem then
        if script.Error then
            state.this_action = prev_action
            return false, script.Error

        elseif not script.Conditions then
            state.this_action = prev_action
            return true

        end

        local result = script.Conditions()
        state.this_action = prev_action
        return result
    end

    if not script.Modifiers[ elem ] then
        state.this_action = prev_action
        return nil, elem .. " not set."
    end

    local success, value = pcall( script.Modifiers[ elem ] )

    if success then
        state.this_action = prev_action
        return value
    end

    state.this_action = prev_action
    return false
end


function scripts:CheckVariable( scriptID )
    local script = self.DB[ scriptID ]

    if not script then
        return false, "no script"

    elseif script.Error then
        return false, script.Error

    end

    local mods = script.Modifiers

    if mods.value then
        local s, val = pcall( mods.value )
        if s then return val end
    end

    return false, "no op or error"
end


function scripts:IsTimeSensitive( scriptID )
    local s = self.DB[ scriptID ]

    return s and s.TimeSensitive
end


function scripts:GetModifiers( scriptID, out )
    out = out or {}

    local script = self.DB[ scriptID ]

    if not script then return out end

    for k, v in pairs( script.Modifiers ) do
        local success, value = pcall(v)
        if success then out[ k ] = value end
    end

    return out
end


local scriptsLoaded = false

-- Forever: each list's script IDs ("pack:list:n"), built as the list's scripts load (LoadScript, LoadItemScripts) so
-- the APL walk reads `IDs[ list ][ actID ]` instead of building the string per entry per pass (Engine/Sim/Core.lua).
-- Keyed by the list table itself (weak: a list the profile drops is collected); an entry's ID is a function of its
-- pack, list and index, so a reload overwrites in place.
scripts.IDs = setmetatable( {}, { __mode = "k" } )

local function recordID( lData, id, scriptID )
    local ids = scripts.IDs[ lData ]
    if not ids then
        ids = {}
        scripts.IDs[ lData ] = ids
    end
    ids[ id ] = scriptID
end

-- (windows design v6 §3, §9) The priority's APL windows: the reserved `windows` list's `window` entries, checked with
-- every open_window / close_window line (compile errors E1-E7, §3.4), into one record per window and display for the
-- belief (`def.aplWindows`, keyed `<pack>:<name>#<display>`, Engine/Schema/Tracked.lua ns.SetAplWindows) and the
-- operations bound (§5.5: a line fires at most once per slot and only slot 1 sends). Allocates; load and import only.
local WINDOW_DISPLAYS = { "Primary", "AOE", "Cooldowns", "Interrupts", "Defensives" }
local ENTRY_META = { action = true, window_name = true, enabled = true, description = true, caption = true }
local WINDOW_OPTS = { duration = true, refresh = true, max_duration = true, max_refresh = true, reset_on_target_change = true }
local PLAIN_OPTS = { mode = true, wait_on_ready = true, reset_on_target_change = true }
local STRICT_OPTS = { allow_skip = true, start_on_first = true, hold_off_gcd = true, step_timeout = true, reset_on_target_change = true }
local MODES = { skip = true, wait = true, continue = true }
local NO_APL_WINDOWS = { decls = {}, records = {}, cap = 0, errors = {}, errorAt = {}, byName = {}, seqByID = {}, startByID = {}, nStrict = 0, holdWalk = false, fireIDs = {} }

-- (windows design v6 §7, rulings 10, 19; L1315) a display's Sequences setting: Primary and AOE only, on by default;
-- Cooldowns, Interrupts and Defensives never sequence (a value stored there by an older build is ignored)
local SEQ_DISPLAYS = { Primary = true, AOE = true }
function scripts.SequencesOn( disp )
    if not SEQ_DISPLAYS[ disp ] then return false end
    local d = rawget( Hekili.Engine.settings.displays, disp )
    return not ( d and d.sequences == false )
end
scripts.NoWindows = NO_APL_WINDOWS
scripts.Windows = {} -- pack name -> its CheckWindows result (LoadScripts)
scripts.HiddenLists = {} -- pack name -> list name -> entries: the sequences' generated lists (never saved, §6)
scripts.declaredWindows = {} -- every loaded priority's declared window names (State.lua: read closed when not active)
scripts.appliedWindows = NO_APL_WINDOWS

local function luaWindow( name )
    for _, s in pairs( class.specs ) do
        local w = rawget( s, "windows" )
        if w and w[ name ] then return true end
    end
    return false
end

local function flag( v ) -- an "=1" option: nil (unwritten), else 0 or 1, else false (not a flag)
    if v == nil then return nil end
    v = tonumber( v )
    return ( v == 0 or v == 1 ) and v or false
end

--- `lists`: a priority's lists by name (parsed entries). Returns { decls, records, cap, errors, errorAt }; each error
--- { code, list, line, text, entry }; errorAt: "list:line" -> "code: text" (the line's last error, LoadScript's stamp). The shared empty result when nothing is declared and nothing is wrong.
function scripts.CheckWindows( lists, packName )
    local errors, errorAt, decls, records, byName, cap, fireIDs = {}, {}, {}, {}, {}, 0, {}
    local function err( code, list, i, entry, text )
        errors[ #errors + 1 ] = { code = code, list = list, line = i, entry = entry, text = text }
        errorAt[ list .. ":" .. i ] = code .. ": " .. text
    end

    -- the `windows` list first: "before use" (§3.1)
    for i, e in ipairs( lists.windows or NO_APL_WINDOWS.decls ) do
        local name = e.window_name
        if e.enabled == false then -- luacheck: ignore 542 (a switched-off entry declares nothing)
        elseif e.action ~= "window" then err( "E5", "windows", i, e, "only window entries belong in the windows list" )
        elseif e.criteria ~= nil then err( "E5", "windows", i, e, "a window entry takes no if=" )
        else
            local bad
            for k in pairs( e ) do
                if not ENTRY_META[ k ] and not WINDOW_OPTS[ k ] then bad = k break end
            end
            local d = e.duration == "combat" and "combat" or tonumber( e.duration )
            local maxD, maxR = tonumber( e.max_duration ), tonumber( e.max_refresh )
            if bad then err( "E7", "windows", i, e, "a window entry does not take " .. bad .. "=" )
            elseif type( name ) ~= "string" or name == "" then err( "E6", "windows", i, e, "a window needs name=" )
            elseif d ~= "combat" and not ( d and d > 0 ) then err( "E6", "windows", i, e, name .. ": duration= must be positive seconds or combat" )
            elseif e.max_duration ~= nil and not ( maxD and maxD > 0 ) then err( "E6", "windows", i, e, name .. ": max_duration= must be positive" )
            elseif e.max_refresh ~= nil and not ( maxR and maxR >= 0 and maxR % 1 == 0 ) then err( "E6", "windows", i, e, name .. ": max_refresh= must be a count" )
            elseif flag( e.refresh ) == false or flag( e.reset_on_target_change ) == false then err( "E6", "windows", i, e, name .. ": refresh= and reset_on_target_change= take 0 or 1" )
            elseif byName[ name ] then err( "E2", "windows", i, e, name .. " is declared twice" )
            elseif luaWindow( name ) then err( "E3", "windows", i, e, name .. " is a class window" )
            else
                local decl = { name = name, duration = d, refresh = flag( e.refresh ) == 1, max_duration = maxD, max_refresh = maxR,
                    reset_on_target_change = flag( e.reset_on_target_change ) == 1, keys = {} }
                byName[ name ] = decl
                decls[ #decls + 1 ] = decl
                for _, disp in ipairs( WINDOW_DISPLAYS ) do
                    local key = tostring( packName ) .. ":" .. name .. "#" .. disp
                    decl.keys[ disp ] = key
                    records[ #records + 1 ] = { key = key, duration = d, refresh = decl.refresh or nil, max_duration = maxD,
                        max_refresh = maxR, reset_on_target_change = decl.reset_on_target_change or nil }
                end
            end
        end
    end

    local names = {}
    for list in pairs( lists ) do
        if list ~= "windows" then names[ #names + 1 ] = list end
    end
    table.sort( names )

    -- (§3.3, §9) the sequences, before any line names one: each declares its window, keyed only in the displays with
    -- Sequences on (§7); an unnamed plain one is `default`, further ones `default_2`, ..., an unnamed strict one
    -- `strict_1`, ... (ruling 31, in list-name then line order). Its record lasts the fight ("combat", L1182); a strict
    -- one ends at a later member cast out of order (on_deviation "end", L1181), a plain one has none (stay).
    local seqOn, nSeqKeys = {}, 0
    for _, disp in ipairs( WINDOW_DISPLAYS ) do
        if scripts.SequencesOn( disp ) then seqOn[ #seqOn + 1 ] = disp end
    end
    local nPlain, nStrict, nStrictDecl, seqByID, startByID = 0, 0, 0, {}, {}
    for _, list in ipairs( names ) do
        for i, e in ipairs( lists[ list ] ) do
            local a = e.action
            if e.enabled ~= false and ( a == "sequence" or a == "strict_sequence" ) then
                local strict = a == "strict_sequence"
                local name = e.window_name
                if name == nil or name == "" then
                    if strict then
                        nStrict = nStrict + 1
                        name = "strict_" .. nStrict
                    else
                        nPlain = nPlain + 1
                        name = nPlain == 1 and "default" or ( "default_" .. nPlain )
                    end
                end
                local bad
                for k in pairs( e ) do
                    if not ENTRY_META[ k ] and k ~= "criteria" and k ~= "steps" and not ( strict and STRICT_OPTS or PLAIN_OPTS )[ k ] then bad = k break end
                end
                local st = tonumber( e.step_timeout )
                local fl = flag( e.reset_on_target_change ) == false or flag( e.wait_on_ready ) == false or flag( e.allow_skip ) == false
                    or flag( e.start_on_first ) == false or flag( e.hold_off_gcd ) == false
                if bad then err( "E7", list, i, e, a .. " does not take " .. bad .. "=" )
                elseif e.mode ~= nil and not MODES[ e.mode ] then err( "E7", list, i, e, "mode= takes skip, wait or continue" )
                elseif e.mode ~= nil and e.wait_on_ready ~= nil then err( "E7", list, i, e, "mode= and wait_on_ready= together" )
                elseif e.step_timeout ~= nil and not ( st and st > 0 ) then err( "E6", list, i, e, name .. ": step_timeout= must be positive seconds" )
                elseif fl then err( "E6", list, i, e, name .. ": a flag takes 0 or 1" )
                elseif byName[ name ] then err( "E2", list, i, e, name .. " is declared twice" )
                elseif luaWindow( name ) then err( "E3", list, i, e, name .. " is a class window" )
                else
                    -- the members as ability keys; one the class does not have is dropped (both sides drop it alike)
                    local steps, members = {}, {}
                    for _, m in ipairs( e.steps or NO_APL_WINDOWS.decls ) do
                        if m.action and class.abilities[ m.action ] then
                            steps[ #steps + 1 ], members[ #members + 1 ] = class.abilities[ m.action ].key, m
                        end
                    end
                    local mode = e.mode or ( flag( e.wait_on_ready ) == 1 and "wait" ) or "skip"
                    local decl = { name = name, duration = "combat", steps = steps, strict = strict, seq = true,
                        mode = not strict and mode or nil, allow_skip = strict and flag( e.allow_skip ) == 1,
                        start_on_first = strict and flag( e.start_on_first ) == 1, hold_off_gcd = strict and flag( e.hold_off_gcd ) == 1,
                        step_timeout = st, reset_on_target_change = flag( e.reset_on_target_change ) == 1, keys = {},
                        on_deviation = strict and "end" or nil,
                        entry = e, list = list, line = i }
                    byName[ name ] = decl
                    decls[ #decls + 1 ] = decl
                    -- the generated lines (§6): script IDs and the hidden lists, compiled by LoadScripts. `memberIDs`: each
                    -- member's own if=; `seq:<name>`: one line per position K under `window.<name>.step=K`, so a repeated
                    -- member is judged by the condition at the due position (the plain sequence's in-place lines and the
                    -- strict hold); `seqstart:<name>` (strict): the start line's members
                    local id = tostring( packName ) .. ":" .. list .. ":" .. i
                    decl.id, decl.members, decl.memberIDs = id, members, {}
                    decl.skipID, decl.giveID, decl.hidden, decl.startList = id .. ":skip", id .. ":give", "seq:" .. name, "seqstart:" .. name
                    fireIDs[ #fireIDs + 1 ] = id
                    fireIDs[ #fireIDs + 1 ] = decl.skipID
                    fireIDs[ #fireIDs + 1 ] = decl.giveID
                    decl.hiddenEntries, decl.startEntries, decl.hiddenIDs, decl.startIDs = {}, {}, {}, {}
                    for k, m in ipairs( members ) do
                        decl.memberIDs[ k ] = id .. ":" .. k
                        local h, st = {}, {}
                        for f, v in pairs( m ) do h[ f ], st[ f ] = v, v end
                        local own = m.criteria and m.criteria ~= "" and ( "&(" .. m.criteria .. ")" ) or ""
                        h.criteria, h.enabled, st.enabled = "window." .. name .. ".step=" .. k .. own, true, true
                        decl.hiddenEntries[ k ], decl.startEntries[ k ] = h, st
                        decl.hiddenIDs[ k ] = tostring( packName ) .. ":" .. decl.hidden .. ":" .. k
                        decl.startIDs[ k ] = tostring( packName ) .. ":" .. decl.startList .. ":" .. k
                        startByID[ decl.startIDs[ k ] ] = decl
                    end
                    seqByID[ id ] = decl
                    if strict then nStrictDecl = nStrictDecl + 1 end
                    for _, disp in ipairs( seqOn ) do
                        local key = tostring( packName ) .. ":" .. name .. "#" .. disp
                        decl.keys[ disp ] = key
                        nSeqKeys = nSeqKeys + 1
                        records[ #records + 1 ] = { key = key, duration = "combat", steps = steps, strict = strict or nil,
                            allow_skip = decl.allow_skip or nil, step_timeout = st, on_deviation = strict and "end" or nil,
                            reset_on_target_change = decl.reset_on_target_change or nil }
                    end
                end
            end
        end
    end
    -- a pass sends at most: the open, the skip (plain) or the give-up (strict), the chosen OPEN and its STEP (§5.5)
    cap = cap + 4 * nSeqKeys

    -- `holdWalk` (L1270): a hold_off_gcd=1 hold walks the normal lists only when a line there could act (a window or
    -- variable line, enabled or not, in any list: a superset on purpose)
    local holdWalk = false
    for _, list in ipairs( names ) do
        for i, e in ipairs( lists[ list ] ) do
            local a = e.action
            if a == "open_window" or a == "close_window" or a == "variable" then holdWalk = true end
            if a == "open_window" or a == "close_window" or a == "restart_sequence" then
                fireIDs[ #fireIDs + 1 ] = tostring( packName ) .. ":" .. list .. ":" .. i
            end
            if e.enabled == false then -- luacheck: ignore 542 (a switched-off line is not checked)
            elseif a == "window" then err( "E5", list, i, e, "a window entry belongs in the windows list" )
            elseif ( a == "call_action_list" or a == "run_action_list" ) and e.list_name == "windows" then
                err( "E5", list, i, e, "the windows list cannot be called" )
            elseif a == "open_window" or a == "close_window" then
                local name, bad = e.window_name, nil
                for k in pairs( e ) do
                    if not ENTRY_META[ k ] and k ~= "criteria" then bad = k break end
                end
                if bad then err( "E4", list, i, e, a .. " takes only name= and if= (" .. bad .. "=)" )
                elseif byName[ name ] then cap = cap + #WINDOW_DISPLAYS
                elseif not luaWindow( name ) then err( "E1", list, i, e, "window " .. tostring( name ) .. " is not declared" ) end
            elseif a == "restart_sequence" then
                local name = e.window_name
                if name == nil or name == "" then name = "default" end -- SimC: a bare restart_sequence restarts `default`
                local d = byName[ name ]
                if not ( d and d.seq and not d.strict ) then err( "E1", list, i, e, "restart_sequence: " .. name .. " is not a plain sequence" )
                else cap = cap + #WINDOW_DISPLAYS end
            end
        end
    end

    if #decls == 0 and #errors == 0 then return NO_APL_WINDOWS end
    return { decls = decls, records = records, cap = cap, errors = errors, errorAt = errorAt, byName = byName, seqByID = seqByID,
        startByID = startByID, nStrict = nStrictDecl, holdWalk = holdWalk, fireIDs = fireIDs }
end

-- (windows design v6 §15) the snapshot's two rolling numbers per key (Core.lua winSend, count10): the operations and
-- the opens sent in the last 10 s, in one-second buckets; built here so the walk never allocates them.
scripts.winCount = {}

--- The active pack's APL windows into the belief's def (Tracked.lua ns.SetAplWindows: a new generation) and as the
--- core copy's source (State.lua BuildWindows reads scripts.appliedWindows). Before a Build (Activation.lua) and when
--- the active pack or its scripts change (Core.lua Hekili.Update). Allocates only a key's snapshot counters, the
--- first time that key is applied.
function scripts:ApplyWindows( packName )
    local cw = packName and self.Windows[ packName ] or NO_APL_WINDOWS
    self.appliedWindows = cw
    ns.SetAplWindows( cw.records, cw.cap )
    local counts = self.winCount
    for i = 1, #cw.records do
        local key = cw.records[ i ].key
        if not counts[ key ] then
            local c = { sec = {}, ops = {}, opens = {} }
            for b = 1, 10 do c.sec[ b ], c.ops[ b ], c.opens[ b ] = -1, 0, 0 end
            counts[ key ] = c
        end
    end
end

local reportedWindowErrors = {} -- LoadScripts: the window compile errors already reported this session

local function scriptLoader()
    if not Hekili.LoadingScripts and not scriptsLoaded then scripts:LoadScripts() end
end

function Hekili:ScriptsLoaded()
    return scriptsLoaded
end


local channelModifiers = {
    interrupt = 1,
    interrupt_if = 1,
    interrupt_immediate = 1,
    interrupt_global = 1,
    chain = 1,
    early_chain_if = 1,
}


function scripts:SwapScripts( s1, s2 )
    local swap = scripts.DB[ s1 ]
    scripts.DB[ s1 ] = scripts.DB[ s2 ]
    scripts.DB[ s2 ] = swap

    -- CN25: the editor moved a line (its list is already reordered): the pure variables' script IDs follow it
    local pack = s1:match( "^(.*):[^:]*:%d+$" )
    if pack then scripts:MarkPure( pack ) end

    -- a pack with windows or window errors: the checks (and errorAt, LoadScript's stamp) follow the lines' new order
    local w = pack and scripts.Windows[ pack ]
    if w and ( #w.decls > 0 or #w.errors > 0 ) then Hekili:LoadScripts() end
end


-- CN25: pack `pack`'s pure variables, each read in place (State.lua) and never registered (Core.lua): a `variable` line
-- marked pure=1 (explicit: a line without it is a stock variable, whatever its shape), enabled, with a value and no if=,
-- value_else= or op but set, the only line of its name, in default or a list reached only by unconditional calls from
-- default. A pure=1 line that is not raises at load (the line and the reason) and is read as a stock variable.
-- PackInfo[pack].pure maps each variable name to its line's script ID (false: not pure), pureText to its value. Returns
-- whether a name's purity or a pure value's text changed (a line's compiled rechecks and time-sensitivity read them:
-- Hekili:LoadScript then reloads the pack). Runs only outside the load's own loop (load time and editor edits).
function scripts:MarkPure( pack )
    local pData, info = Hekili.Engine.settings.packs[ pack ], self.PackInfo[ pack ]
    if not ( pData and info ) then return false end

    -- the lists every call to which is unconditional from a list already reached so (default first)
    local reach, count, grew = { default = true }, {}, true
    while grew do
        grew = false
        for list in pairs( pData.lists ) do
            if not reach[ list ] then
                local called, ok = false, true
                for from, fData in pairs( pData.lists ) do
                    for _, e in ipairs( fData ) do
                        if e.list_name == list and e.enabled ~= false and ( e.action == "call_action_list" or e.action == "run_action_list" ) then
                            called = true
                            ok = ok and reach[ from ] and ( e.criteria or "" ) == "" and ( e.strict_if or "" ) == ""
                        end
                    end
                end
                if called and ok then reach[ list ], grew = true, true end
            end
        end
    end
    for _, lData in pairs( pData.lists ) do
        for _, e in ipairs( lData ) do
            if e.action == "variable" and e.var_name then count[ e.var_name ] = ( count[ e.var_name ] or 0 ) + 1 end
        end
    end

    local pure, text = {}, {}
    for list, lData in pairs( pData.lists ) do
        for id, e in ipairs( lData ) do
            local name = e.action == "variable" and e.var_name
            if name then
                local at = pack .. ":" .. list .. ":" .. id
                local why
                if tonumber( e.pure ) == 1 and e.enabled ~= false then
                    why = ( e.criteria or "" ) ~= "" and "if= is set"
                        or ( e.value_else or "" ) ~= "" and "value_else= is set"
                        or ( e.op or "set" ) ~= "set" and ( "op=" .. e.op )
                        or ( e.value or "" ) == "" and "no value="
                        or count[ name ] > 1 and ( count[ name ] .. " lines of the name" )
                        or not reach[ list ] and "its list is reached through a conditional call (or not from default)"
                    if why then
                        Hekili:Error( ( "Pure variable '%s' at %s: %s; it is read as a stock variable." ):format( name, at, why ) )
                    end
                end
                pure[ name ] = not why and tonumber( e.pure ) == 1 and e.enabled ~= false and count[ name ] == 1 and at
                text[ name ] = e.value
            end
        end
    end

    -- a pure variable whose value reads itself, directly or through other pure variables, would recurse at every read
    local function loops( root, name, seen )
        for ref in ( text[ name ] or "" ):gmatch( "variable%.([%w_]+)" ) do
            if ref == root then return true end
            if pure[ ref ] and not seen[ ref ] then
                seen[ ref ] = true
                if loops( root, ref, seen ) then return true end
            end
        end
        return false
    end
    local looped = {}
    for name, at in pairs( pure ) do
        if at and loops( name, name, {} ) then looped[ name ] = at end
    end
    for name, at in pairs( looped ) do
        Hekili:Error( ( "Pure variable '%s' at %s: its value reads itself; it is read as a stock variable." ):format( name, at ) )
        pure[ name ] = false
    end

    local old, oldText = info.pure or {}, info.pureText or {}
    info.pure, info.pureText = pure, text
    for name, v in pairs( pure ) do
        if not v ~= not old[ name ] then return true end
        if v and text[ name ] ~= oldText[ name ] then return true end -- its readers' time-sensitivity reads the text
    end
    for name, v in pairs( old ) do
        if v and pure[ name ] == nil then return true end
    end
    return false
end


-- (windows design v6 §6) pack `pack`'s sequences' generated lines: its members' own conditions and its hidden lists.
-- LoadScripts, and Hekili:LoadScript's pure-variable reload (L1329: those lines read pure values too).
function scripts:LoadSequences( pack )
    self.HiddenLists[ pack ] = {}
    for _, d in ipairs( self.Windows[ pack ].decls ) do
        if d.seq then
            self.HiddenLists[ pack ][ d.hidden ], self.HiddenLists[ pack ][ d.startList ] = d.hiddenEntries, d.startEntries
            for k, m in ipairs( d.members ) do
                self.DB[ d.memberIDs[ k ] ] = ConvertScript( m, false, d.memberIDs[ k ] )
                for _, h in ipairs( { { d.hiddenEntries, d.hiddenIDs, d.hidden }, { d.startEntries, d.startIDs, d.startList } } ) do
                    local sid = h[ 2 ][ k ]
                    Hekili:LoadScript( pack, h[ 3 ], k, h[ 1 ], sid ) -- an ordinary line's bookkeeping (off-GCD, channels, items, auras)
                    self.DB[ sid ].ReadsWindow = true
                end
            end
        end
    end
end


function scripts:LoadScripts()
    if not Hekili.PLAYER_ENTERING_WORLD then
        C_Timer.After( 1, scriptLoader )
        return
    end

    local settings = Hekili.Engine.settings
    wipe( self.DB )
    wipe( self.Channels )
    wipe( self.PackInfo )
    wipe( self.Windows )
    wipe( self.declaredWindows )
    wipe( self.HiddenLists )

    Hekili.LoadingScripts = true

    state.reset()

    for pack, pData in pairs( settings.packs ) do
        local specData = pData.spec and class.specs[ pData.spec ]

        if specData then
            self.PackInfo[ pack ] = {
                items = {},
                auras = {},
                hasOffGCD = false,
                hasWhileCasting = false
            }

            self:MarkPure( pack )
            -- (windows design v6 §9) the priority's windows first: a line reading one compiles against a known name
            local cw = scripts.CheckWindows( pData.lists, pack )
            self.Windows[ pack ] = cw
            for _, d in ipairs( cw.decls ) do self.declaredWindows[ d.name ] = true end

            for list, lData in pairs( pData.lists ) do
                for action, _ in ipairs( lData ) do
                    Hekili:LoadScript( pack, list, action )
                end
            end

            self:LoadSequences( pack )

            -- (windows design v6 §3.4) a window compile error disables its line (the walk skips a script with an Error)
            for _, e in ipairs( cw.errors ) do
                local script = self.DB[ pack .. ":" .. e.list .. ":" .. e.line ]
                local text = e.code .. ": " .. e.text
                if script then script.Error = text end
                local seen = pack .. ":" .. e.list .. ":" .. e.line .. " " .. text
                if not reportedWindowErrors[ seen ] then -- once per line and error a session: every options edit loads again
                    reportedWindowErrors[ seen ] = true
                    Hekili:Error( "Priority '%s' list '%s' line %d: %s: %s; the line is skipped.", pack, e.list, e.line, e.code, e.text )
                end
            end
        end
    end

    Hekili.LoadingScripts = false
    scriptsLoaded = true
end


function Hekili:LoadScripts()
    self.Scripts:LoadScripts()
    self:UpdateUseItems()
end


function Hekili:IsItemScripted( token, specific )
    local pack = Hekili:GetActivePack()
    if not pack then return false end
    if not self.Scripts.PackInfo[ pack ] then return false end

    if self.Scripts.PackInfo[ pack ].items[ token ] then return true end
    if not specific and ( ( state.trinket.t1.is[ token ] and self.Scripts.PackInfo[ pack ].items.trinket1 ) or ( state.trinket.t2.is[ token ] and self.Scripts.PackInfo[ pack ].items.trinket2 ) ) then return true end

    return false
end


function Hekili.Scripts:LoadItemScripts()
    for k in pairs( self.DB ) do
        if k:sub( 9 ) == "UseItems:" then
            self.DB[ k ] = nil
        end
    end

    local pack = "UseItems"

    for list, lData in pairs( class.itemPack.lists ) do
        local specData = class.specs[ state.spec.id ]

        for action, data in ipairs( lData ) do
            local scriptID = pack .. ":" .. list .. ":" .. action
            recordID( lData, action, scriptID )

            local script = ConvertScript( data, true, scriptID )
            local lua = script.Lua

            if lua then
                for aura in lua:gmatch( "d?e?buff%.([a-z_0-9]+)" ) do
                    self.PackInfo[ pack ].auras[ aura ] = true
                end

                for aura in lua:gmatch( "active_dot%.([a-z_0-9]+)" ) do
                    self.PackInfo[ pack ].auras[ aura ] = true
                end
            end

            if data.use_off_gcd and data.use_off_gcd ~= 0 then
                self.PackInfo[ pack ].hasOffGCD = true
            end

            if data.use_while_casting and data.use_while_casting ~= 0 then
                self.PackInfo[ pack ].hasWhileCasting = true
            end

            if data.action == "call_action_list" or data.action == "run_action_list" then
                -- Check for Time Sensitive conditions.
                script.TimeSensitive = false

                if lua then
                    -- If resources are checked, it's time-sensitive.
                    for k in pairs( GetResourceInfo() ) do
                        local resource = specData.resources[ k ]
                        resource = resource and resource.state

                        if resource and lua:find( k ) and ( resource.regenModel or resource.regen ~= 0.001 ) then
                            script.TimeSensitive = true
                            break
                        end
                    end

                    if not script.TimeSensitive then
                        -- Check for other time-sensitive variables.
                        if lua:find( "time" ) or lua:find( "cooldown" ) or lua:find( "charge" ) or lua:find( "remain" ) or lua:find( "up" ) or lua:find( "down" ) or lua:find( "ticking" ) or lua:find( "refreshable" ) or lua:find( "stealthed" ) or lua:find( "rune" ) then
                            script.TimeSensitive = true
                        end
                    end
                end
            end

            local ability

            if data.action then
                ability = specData.abilities[ data.action ] or class.abilities[ data.action ]
            end

            if ability then
                if ability.channeled then
                    if not self.Channels[ pack ] then self.Channels[ pack ] = {} end
                    if not self.Channels[ pack ][ data.action ] then
                        self.Channels[ pack ][ data.action ] = {}
                    end

                    local cInfo = self.Channels[ pack ][ data.action ]

                    -- This will load the channel criteria for the first entry for this ability in any of the action lists.
                    -- This seems OK as long as channel breakage criteria is based on the same logic for the same spell.
                    -- There's genuinely no way to know if a person is channeling Mind Flay because it was recommended, or just because they felt like it.
                    -- 2020-10-22:  Modified this to decide that if any breakchannel logic is met, you break the channel.
                    -- TODO:  Phase 3 would be only using channel-break logic for channel entries that you've passed in the current APL run.

                    for k in pairs( channelModifiers ) do
                        if script.Modifiers[ k ] then
                            local newfunc = script.Modifiers[ k ]

                            if newfunc and type( newfunc ) == "function" then
                                local oldfunc = cInfo[ k ]

                                if oldfunc then
                                    local oldstr = cInfo[ "_" .. k ]
                                    cInfo[ k ] = setfenv( function() return ( oldfunc() ) or ( newfunc() ) end, state )
                                    cInfo[ "_" .. k ] = format( "( %s ) or ( %s )", oldstr or "nil", script.ModEmulates[ k ] )
                                else
                                    cInfo[ "_" .. k ] = script.ModEmulates[ k ]
                                    cInfo[ k ] = script.Modifiers[ k ]
                                end
                            end
                        end
                    end
                end
            end

            self.DB[ scriptID ] = script
        end
    end
end


function Hekili:LoadItemScripts()
    self.Scripts:LoadItemScripts()
end


-- Whether condition `lua` reads something that moves with time; CN25: a pure variable's (`info`: the pack's PackInfo)
-- value is read through, as when its text was inlined (`seen`: the variables followed).
local function timeSensitive( lua, specData, info, seen )
    -- If resources are checked, it's time-sensitive.
    for k in pairs( GetResourceInfo() ) do
        local resource = specData.resources[ k ]
        resource = resource and resource.state

        if resource and lua:find( k ) and ( resource.regenModel or resource.regen ~= 0.001 ) then
            return true
        end
    end

    -- Check for other time-sensitive variables.
    if lua:find( "time" ) or lua:find( "cooldown" ) or lua:find( "charge" ) or lua:find( "remain" ) or lua:find( "up" ) or lua:find( "down" ) or lua:find( "ticking" ) or lua:find( "refreshable" ) or lua:find( "stealthed" ) or lua:find( "rune" ) then
        return true
    end

    for name in lua:gmatch( "variable%.([a-z0-9_]+)" ) do
        local text = info and info.pure and info.pure[ name ] and info.pureText[ name ]
        if text and not seen[ name ] then
            seen[ name ] = true
            if timeSensitive( text, specData, info, seen ) then return true end
        end
    end
    return false
end


-- `entries`, `scriptID`: a sequence's generated list and its line's ID (windows design v6 §6), else the pack's list.
function Hekili:LoadScript( pack, list, id, entries, scriptID )
    local pData = Hekili.Engine.settings.packs[ pack ]
    entries = entries or pData.lists[ list ]
    local data = entries[ id ]
    local specData = pData.spec and class.specs[ pData.spec ]
    scriptID = scriptID or pack .. ":" .. list .. ":" .. id
    recordID( entries, id, scriptID )

    -- CN25: an edited `variable` or list-call line outside a full load (a call's condition, state or target sets which
    -- lists a pure line may sit in): the pack's pure map follows it, and a change in which names are pure or in a pure
    -- value reloads every line of the pack (their rechecks and time-sensitivity read through pure variables)
    if not Hekili.LoadingScripts
        and ( data.action == "variable" or data.action == "call_action_list" or data.action == "run_action_list" )
        and scripts:MarkPure( pack ) then
        Hekili.LoadingScripts = true
        for l, lData in pairs( pData.lists ) do
            for i in ipairs( lData ) do
                Hekili:LoadScript( pack, l, i )
            end
        end
        if scripts.Windows[ pack ] then scripts:LoadSequences( pack ) end
        Hekili.LoadingScripts = false
        return
    end

    local info = scripts.PackInfo[ pack ]
    loadingPure = info and info.pure
    local script = ConvertScript( data, true, scriptID )
    loadingPure = nil

    if script.Error then
        Hekili:Error( "Error in " .. scriptID .. " conditions:  " .. ( script.rs or "null" ) .. "\n\n" .. script.Error )
    end

    -- (windows design v6 §3.4) a pack list line keeps its window compile error on every reload, not only the full
    -- load's (LoadScripts reports it); the walk skips a script with an Error
    local cw = entries == pData.lists[ list ] and scripts.Windows[ pack ]
    if cw and cw.errorAt[ list .. ":" .. id ] then script.Error = cw.errorAt[ list .. ":" .. id ] end

    -- Forever: target health is secret, so the belief answers it with constants (spec §6.5, §7.4); time to die is unwarned.
    local scan = ns.AplSecretToken
    local token, subject, reads = scan( data.criteria )
    if not token then token, subject, reads = scan( data.value ) end
    if not token then token, subject, reads = scan( data.value_else ) end
    if not token then token, subject, reads = scan( data.target_if ) end
    if token then
        Hekili:Error( "Forever: %s; `%s` in pack `%s` list `%s` entry %d (%s) %s.", subject, token, pack, list, id, data.action or "?", reads )
    end

    script.action = data.action
    local lua = script.Lua
    script.ReadsWindow = lua ~= nil and lua:find( "window%." ) ~= nil -- its recheck adds the windows' times (State.lua)

    if lua then
        for aura in lua:gmatch( "d?e?buff%.([a-z_0-9]+)" ) do
            scripts.PackInfo[ pack ].auras[ aura ] = true
        end

        for aura in lua:gmatch( "active_dot%.([a-z_0-9]+)" ) do
            scripts.PackInfo[ pack ].auras[ aura ] = true
        end
    end

    if data.use_off_gcd and data.use_off_gcd ~= 0 then
        scripts.PackInfo[ pack ].hasOffGCD = true
    end

    if data.use_while_casting and data.use_while_casting ~= 0 then
        scripts.PackInfo[ pack ].hasWhileCasting = true
    end

    if data.action == "call_action_list" or data.action == "run_action_list" then
        -- Check for Time Sensitive conditions.
        script.TimeSensitive = false

        if lua then
            script.TimeSensitive = timeSensitive( lua, specData, info, {} )
        end
    end

    local ability

    if data.action then
        ability = specData.abilities[ data.action ] or class.abilities[ data.action ]
    end

    if ability then
        if ability.channeled then
            if not scripts.Channels[ pack ] then scripts.Channels[ pack ] = {} end
            if not scripts.Channels[ pack ][ data.action ] then
                scripts.Channels[ pack ][ data.action ] = {}
            end

            local cInfo = scripts.Channels[ pack ][ data.action ]

            -- This will load the channel criteria for the first entry for this ability in any of the action lists.
            -- This seems OK as long as channel breakage criteria is based on the same logic for the same spell.
            -- There's genuinely no way to know if a person is channeling Mind Flay because it was recommended, or just because they felt like it.
            -- 2020-10-22:  Modified this to decide that if any breakchannel logic is met, you break the channel.
            -- TODO:  Phase 3 would be only using channel-break logic for channel entries that you've passed in the current APL run.

            for k in pairs( channelModifiers ) do
                if script.Modifiers[ k ] then
                    local newfunc = script.Modifiers[ k ]

                    if newfunc and type( newfunc ) == "function" then
                        local oldfunc = cInfo[ k ]

                        if oldfunc then
                            local oldstr = cInfo[ "_" .. k ]
                            cInfo[ k ] = setfenv( function() return ( oldfunc() ) or ( newfunc() ) end, state )
                            cInfo[ "_" .. k ] = format( "( %s ) or ( %s )", oldstr or "nil", script.ModEmulates[ k ] )
                        else
                            cInfo[ "_" .. k ] = script.ModEmulates[ k ]
                            cInfo[ k ] = script.Modifiers[ k ]
                        end
                    end
                end
            end
        end

        if list ~= "precombat" and data.enabled then
            if ( ability.item or data.action == "trinket1" or data.action == "trinket2" or data.action == "main_hand" ) then
                scripts.PackInfo[ pack ].items[ data.action ] = true
            end
        end
    end

    scripts.DB[ scriptID ] = script
end



function scripts:ImplantDebugData( data )
    local prev = state.this_action
    state.this_action = data.actionName

    if data.hook then
        local s = self.DB[ data.hook ]
        local pack, list, entry = data.hook:match( "^(.-):(.-):(.-)$" )

        data.HookHeader = "Called from " .. pack .. ", " .. list .. ", " .. "#" .. entry .. "."
        data.HookScript = s.SimC
        data.HookElements = data.HookElements or {}

        self:StoreValues( data.HookElements, s )
    end

    if data.script then
        local s = self.DB[ data.script ]
        data.ActScript = s.SimC
        data.ActElements = data.ActElements or {}
        self:StoreValues( data.ActElements, s )
    end

    state.this_action = prev
end


local key_cache = setmetatable( {}, {
    __index = function( t, k )
        t[k] = k:gsub( "(%S+)%[(%d+)]", "%1.%2" ):gsub( "(%S+)%['([%a%w_]+)']", "%1.%2" )
        return t[k]
    end
})


local checked = {}

local function embedConditionsAndValues( source, elements )
    if source and source ~= "" then
        local wasDebugging = Hekili.ActiveDebug
        Hekili.ActiveDebug = false

        if elements then
            wipe( checked )

            for k, v in pairs( elements ) do
                if not checked[ k ] then
                    local key = key_cache[ k ]
                    local success, value = pcall( v, true )

                    if type( value ) == "number" then
                        if source == key then
                            source = source .. "[" .. tostring( value ) .. "]"
                        else
                            source = source:gsub( "([^a-z0-9_.[])("..key..")([^a-z0-9_.[])", format( "%%1%%2[%.2f]%%3", value ) )
                            source = source:gsub( "^("..key..")([^a-z0-9_.[])", format( "%%1[%.2f]%%2", value ) )
                            source = source:gsub( "([^a-z0-9_.[])("..key..")$", format( "%%1%%2[%.2f]", value ) )
                        end
                    elseif type( value ) == "boolean" then
                        if source == key then
                            source = source .. "[" .. tostring( value ) .. "]"
                        else
                            source = source:gsub( "([^a-z0-9_.[])("..key..")([^a-z0-9_.[])", format( "%%1%%2[%s]%%3", tostring( value ) ) )
                            source = source:gsub( "^("..key..")([^a-z0-9_.[])", format( "%%1[%s]%%2", tostring( value ) ) )
                            source = source:gsub( "([^a-z0-9_.[])("..key..")$", format( "%%1%%2[%s]", tostring( value ) ) )
                        end
                    end

                    checked[ k ] = true
                end
            end

        end

        if wasDebugging then Hekili.ActiveDebug = true end
        return source
    end

    return "NONE"
end



do
    local troubleshootingSnapshotTimes = false

    function scripts:GetConditionsAndValues( scriptID, listName, actID, recheck )
        if troubleshootingSnapshotTimes or not Hekili.ActiveDebug then return "[no data]" end

        if listName and actID then
            scriptID = scriptID .. ":" .. listName .. ":" .. actID
        end

        local script = self.DB[ scriptID ]

        if recheck then
            return embedConditionsAndValues( script.RecheckScript, script.RecheckElements )
        end

        if script.Print then return script.Print() end

        return embedConditionsAndValues( script.SimC, script.Elements )
    end
end


function scripts:GetModifierValues( modifier, scriptID, listName, actID )
    if listName and actID then
        scriptID = scriptID .. ":" .. listName .. ":" .. actID
    end

    local script = self.DB[ scriptID ]

    if script and script.ModSimC[ modifier ] and script.ModSimC[ modifier ].SimC ~= "" then
        local output = script.ModSimC[ modifier ]

        wipe( checked )

        for k, v in pairs( script.ModElements[ modifier ] ) do
            if not checked[ k ] then
                local key = key_cache[ k ]
                local success, value = pcall( v )

                if type( value ) == 'number' then
                    if output == key then
                        output = output .. "[" .. tostring( value ) .. "]"
                    else
                        output = output:gsub( "([^a-z0-9_.[])("..key..")([^a-z0-9_.[])", format( "%%1%%2[%.2f]%%3", value ) )
                        output = output:gsub( "^("..key..")([^a-z0-9_.[])", format( "%%1[%.2f]%%2", value ) )
                        output = output:gsub( "([^a-z0-9_.[])("..key..")$", format( "%%1%%2[%.2f]", value ) )
                    end
                else
                    if output == key then
                        output = output .. "[" .. tostring( value ) .. "]"
                    else
                        output = output:gsub( "([^a-z0-9_.[])("..key..")([^a-z0-9_.[])", format( "%%1%%2[%s]%%3", tostring( value ) ) )
                        output = output:gsub( "^("..key..")([^a-z0-9_.[])", format( "%%1[%s]%%2", tostring( value ) ) )
                        output = output:gsub( "([^a-z0-9_.[])("..key..")$", format( "%%1%%2[%s]", tostring( value ) ) )
                    end
                end

                checked[ k ] = true
            end
        end

        return output
    end

    return "NONE"
end

Hekili.dumpKeyCache = key_cache
