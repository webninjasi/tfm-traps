import xml.etree.ElementTree as ET
import os
import re

from os.path import splitext, join


OUTPUT_DIR = 'lua/levels'
GROUND_COMMANDS = [
    'hide',
    'show',
    'toggle',
    'move',
    'height',
    'width',
    'damping',
    'color',
    'foreground',
    'fixed',
    'mass',
    'restitution',
    'friction',
    'collision',
    'angle',
    'dynamic',
    'type',
    'image',
]


levelXML = {}
traps = {}


def default_collision(t):
    if t == '15' or t == '9':
        return 4
    return 1

def default_foreground(t):
    if t == '15' or t == '9':
        return True
    return False

def tonumber(val, base=10):
    if not val:
        return None

    try:
        return int(val, base)
    except ValueError:
        return None

def tofloat(val):
    if not val:
        return None

    try:
        return float(val)
    except ValueError:
        return None

def parse_ground_tag(ground):
    props = ground.get("P", "").split(",")
    collision = tonumber(ground.get("c")) or default_collision(ground.get("T"))

    return {
        "x": ground.get("X", 0),
        "y": ground.get("Y", 0),

        "type": ground.get("T", 0),
        "width": ground.get("L", 10),
        "height": ground.get("H", 10),
        "color": ground.get("o") and tonumber(ground.get("o"), 16) or None,
        "miceCollision": collision in (1, 3) and "true" or "false",
        "groundCollision": collision < 3 and "true" or "false",
        "dynamic": tonumber(props[0]) != 0 and "true" or "false",
        "mass": tonumber(props[1]) or 0,
        "friction": tofloat(props[2]) or 0,
        "restitution": tofloat(props[3]) or 0,
        "angle": tonumber(props[4]) or 0,
        "foreground": ground.get("N", default_foreground(ground.get("T"))) and "true" or "false",
        "fixedRotation": tonumber(props[5]) != 0 and "true" or "false",
        "linearDamping": tofloat(props[6]) or 0,
        "angularDamping": tofloat(props[7]) or 0,
    }

def parse_trap_commands(text, noground):
    if not text:
        return []

    commands = text.split(";")
    ret = []

    for cmd in commands:
        match = re.match(r'^([a-zA-Z]+)(.*)$', cmd.strip())

        if match:
            trap_type = match.group(1)
            params = match.group(2)

            if not noground or trap_type not in GROUND_COMMANDS:
                ret += [
                    {
                        "type": trap_type,
                        "params": params is not None and params.lstrip().split(","),
                    }
                ]
        else:
            print("Invalid trap command:", cmd)

    return ret

def parse_groups(text):
    if not text:
        return []

    groups = text.split(";")
    ret = []

    for group in groups:
        params = group.split(',')
        ret += [
            {
                "name": params[0],
                "behaviour": len(params) > 1 and params[1] or None,
            }
        ]

    return ret

def parse_image(image, params):
    if not image:
        return None

    parts = image.split(',')
    if len(parts) < 3:
        return None

    x = tonumber(parts[0])
    y = tonumber(parts[1])
    url = parts[2]

    if x is None or y is None or len(url) < 12:
        return None

    ret = [url, str(x), str(y)]

    if not params:
        return ret

    parts = params.split(',')
    if len(parts) == 0:
        return ret

    parts = [tonumber(part) or 'nil' for part in parts]
    parts = [str(part) for part in parts]

    return ret + parts

def parse_timing(text):
    if not text:
        return []

    timings = text.split(",")

    for i in range(len(timings)):
        timings[i] = tonumber(timings[i])

    return timings

def read_xmls():
    for name in os.listdir("maps/"):
        print(f"maps/{name}")
        levelXML[name] = ET.parse(f"maps/{name}")

def parse_traps():
    for (name, xml) in levelXML.items():
        traps[name] = []
        root = xml.getroot()
        lua_id = 1

        for elm in root.iter():
            if elm.text:
                elm.text = elm.text.strip()
            if elm.tail:
                elm.tail = elm.tail.strip()

        ground_root = root.find('Z').find('S')
        ground_index_mapping = {}
        ground_index = 0
        ground_current_index = 0

        for ground in ground_root.findall('S'):
            ground_index_mapping[str(ground_index)] = str(ground_current_index)
            ground_index += 1

            if ground.get("lua") or ground.get("onactivate") or ground.get("ondeactivate") or ground.get("ontouch") or ground.get("ontimer") or ground.get("template"):
                durations = parse_timing(ground.get("duration"))
                reloads = parse_timing(ground.get("reload"))
                noground = ground.get("noground", None) != None
                trapReload = reloads[0] if len(reloads) > 0 else None
                trapReload = "TRAP_RELOAD" if trapReload == None else trapReload
                timerReload = reloads[1] if len(reloads) > 1 else None
                timerReload = "nil" if timerReload == None else timerReload
                traps[name] += [
                    {
                        "id": lua_id,
                        "name": ground.get("lua", ""),
                        "groups": parse_groups(ground.get("groups")),
                        "onactivate": parse_trap_commands(ground.get("onactivate"), noground),
                        "ondeactivate": parse_trap_commands(ground.get("ondeactivate"), noground),
                        "ontouch": parse_trap_commands(ground.get("ontouch"), noground),
                        "ontimer": parse_trap_commands(ground.get("ontimer"), noground),
                        "ground": not noground and parse_ground_tag(ground) or None,
                        "image": parse_image(ground.get("i") or "", ground.get("imgp") or ""),
                        "duration": len(durations) > 0 and durations[0] or "TRAP_DURATION",
                        "reload": trapReload,
                        "timerDuration": len(durations) > 1 and durations[1] or "nil",
                        "timerReload": timerReload,
                        "interval": ground.get("interval") and tonumber(ground.get("interval")) or "1",
                        "delay": ground.get("delay") and tonumber(ground.get("delay")) or "0",
                        "vanish": ground.get("v") and tonumber(ground.get("v")) or None,
                        "template": ground.get("template") or None,
                        "invisible": ground.get("m", None) is not None or False,
                    }
                ]
                lua_id += 1
                ground_root.remove(ground)
            else:
                ground_current_index += 1

        # We need to fix joint target platforms
        joint_root = root.find('Z').find('L')

        for joint in joint_root.findall('.//*'):
            m1 = joint.get("M1")
            m2 = joint.get("M2")

            if m1 and m1 in ground_index_mapping:
                joint.set("M1", ground_index_mapping[m1])

            if m2 and m2 in ground_index_mapping:
                joint.set("M2", ground_index_mapping[m2])

        print(f'Trap Grounds found in {name}: {len(traps[name])}')

def concat_command_params(params):
    if not params:
        return

    return ', '.join([
        f'"{param}"'
        for param in params
    ])

def find_trap(traps, name):
    for trap in traps:
        if trap["name"] == name:
            return trap
    return None

def generate_command_code(lines, cmd):
    lines += [f'          commands["{cmd["type"]}"]({concat_command_params(cmd["params"])}),']

def generate_levels():
    level_requires = []

    for (name, xml) in levelXML.items():
        lines = []
        filename = splitext(name)[0]
        generate_code(lines, name, xml)
        save_lua(join(OUTPUT_DIR, filename + '.lua'), lines)
        level_requires += [f'  ["{filename}"] = pshy.require("levels.{filename}")(commands, TRAP_RELOAD, TRAP_DURATION),']

    lines = [
        'local traps = pshy.require("traps")',
        'local commands = traps.commands',
        'local TRAP_RELOAD = traps.TRAP_RELOAD',
        'local TRAP_DURATION = traps.TRAP_DURATION',
        'return {',
    ]
    lines += level_requires
    lines += ['}']
    save_lua(join(OUTPUT_DIR, 'init.lua'), lines)

def generate_code(lines, name, xml):
    lines += ['return function(commands, TRAP_RELOAD, TRAP_DURATION)']
    lines += [f'  return {{']
    lines += [f'    xml = [[{ET.tostring(xml.getroot(), encoding="unicode")}]],']
    lines += ['    traps = {']

    for original_trap in traps[name]:
        trap = original_trap

        if trap["template"] is not None:
            template_trap = find_trap(traps[name], trap["template"])
            if template_trap is not None:
                new_trap = dict(template_trap)
                new_trap["id"] = trap["id"]
                new_trap["name"] = trap["name"]

                if new_trap["ground"]:
                    new_trap["ground"]["x"] = trap["ground"]["x"]
                    new_trap["ground"]["y"] = trap["ground"]["y"]

                if trap["groups"]:
                    new_trap["groups"] = trap["groups"]

                if trap["onactivate"]:
                    new_trap["onactivate"] = trap["onactivate"]

                if trap["ondeactivate"]:
                    new_trap["ondeactivate"] = trap["ondeactivate"]

                if trap["ontouch"]:
                    new_trap["ontouch"] = trap["ontouch"]

                if trap["ontimer"]:
                    new_trap["ontimer"] = trap["ontimer"]

                if trap["image"]:
                    new_trap["image"] = trap["image"]

                if trap["duration"]:
                    new_trap["duration"] = trap["duration"]

                if trap["reload"]:
                    new_trap["reload"] = trap["reload"]

                if trap["timerDuration"]:
                    new_trap["timerDuration"] = trap["timerDuration"]

                if trap["timerReload"]:
                    new_trap["timerReload"] = trap["timerReload"]

                if trap["interval"]:
                    new_trap["interval"] = trap["interval"]

                if trap["delay"]:
                    new_trap["delay"] = trap["delay"]

                trap = new_trap

        lines += ['      {']
        lines += [f'        id = {trap["id"]},']
        lines += [f'        name = "{trap["name"].replace("#", "")}",']

        lines += ['        groups = {']
        for group in trap["groups"]:
            lines += ['        {']
            lines += [f'          name = "{group["name"]}",']
            lines += [f'          behaviour = {group["behaviour"]},']
            lines += ['        },']
        lines += ['        },']

        lines += ['        onactivate = {']
        for cmd in trap["onactivate"]:
            generate_command_code(lines, cmd)
        lines += ['        },']

        lines += ['        ondeactivate = {']
        for cmd in trap["ondeactivate"]:
            generate_command_code(lines, cmd)
        lines += ['        },']

        lines += ['        ontouch = {']
        for cmd in trap["ontouch"]:
            generate_command_code(lines, cmd)
        lines += ['        },']

        lines += ['        ontimer = {']
        for cmd in trap["ontimer"]:
            generate_command_code(lines, cmd)
        lines += ['        },']

        ground = trap["ground"]

        if ground:
            lines += ['        getGround = function()']
            lines += ['          return {']
            lines += [f'          x = {ground["x"]},']
            lines += [f'          y = {ground["y"]},']

            if trap["invisible"]:
                if ground["type"] == 14:
                    lines += [f'          type = 14,']
                else:
                    lines += ['          type = 12,']
            else:
                lines += [f'          type = {ground["type"]},']

            lines += [f'          width = {ground["width"]},']
            lines += [f'          height = {ground["height"]},']

            if "image" in trap and trap["image"]:
                image = trap["image"]
                params = ','.join(image[1:9])

                if len(image) >= 10:
                    params += ',' + (params[9] == '1' and 'true' or 'false')

                lines += [f'          image = {{"{image[0]}",{params}}},']

            if trap["invisible"]:
                lines += ['          color = 0,']
            else:
                lines += [f'          color = {ground["color"] is None and "nil" or hex(ground["color"])},']

            lines += [f'          miceCollision = {ground["miceCollision"]},']
            lines += [f'          groundCollision = {ground["groundCollision"]},']
            lines += [f'          dynamic = {ground["dynamic"]},']
            lines += [f'          angle = {ground["angle"]},']
            lines += [f'          friction = {ground["friction"]},']
            lines += [f'          restitution = {ground["restitution"]},']
            lines += [f'          foreground = {ground["foreground"]},']
            lines += [f'          fixedRotation = {ground["fixedRotation"]},']
            lines += [f'          linearDamping = {ground["linearDamping"]},']
            lines += [f'          angularDamping = {ground["angularDamping"]},']
            lines += ['          }']
            lines += ['        end,']

        lines += [f'        duration = {trap["duration"]},']
        lines += [f'        reload = {trap["reload"]},']
        lines += [f'        timerDuration = {trap["timerDuration"]},']
        lines += [f'        timerReload = {trap["timerReload"]},']
        lines += [f'        interval = {trap["interval"]},']
        lines += [f'        delay = {trap["delay"]},']
        lines += ['      },']

    lines += ['    },']
    lines += ['  }']
    lines += ['end']

def save_lua(filename, lines):
    with open(filename, 'w', encoding="utf8") as luafile:
        luafile.write('\n'.join(lines))
        print(f"Generated lua code for {filename} successfully!")

read_xmls()
parse_traps()
generate_levels()
