#     NoFlo - Flow-Based Programming for Node.js
#     (c) 2011 Henri Bergius, Nemein
#     NoFlo may be freely distributed under the MIT license
fs = require 'fs'
events = require 'events'
fbp = require './Fbp'

# # NoFlo network graph
#
# This class represents an abstract NoFlo graph containing nodes
# connected to each other with edges.
#
# These graphs can be used for visualization and sketching, but
# also are the way to start a NoFlo network.
class Graph extends events.EventEmitter
    name: ''
    nodes: []
    edges: []
    initializers: []

    # ## Creating new graphs
    #
    # Graphs are created by simply instantiating the Graph class
    # and giving it a name:
    #
    #     myGraph = new Graph 'My very cool graph'
    constructor: (@name) ->
        @nodes = []
        @edges = []
        @initializers = []

    # ## Adding a node to the graph
    #
    # Nodes are identified by an ID unique to the graph. Additionally,
    # a node may contain information on what NoFlo component it is and
    # possible display coordinates.
    #
    # For example:
    #
    #     myGraph.addNode 'Read, 'ReadFile',
    #       x: 91
    #       y: 154
    #
    # Addition of a node will emit the `addNode` event.
    addNode: (id, component, display) ->
        node =
            id: id
            component: component
            display: display
        @nodes.push node
        @emit 'addNode', node

    # ## Removing a node from the graph
    #
    # Existing nodes can be removed from a graph by their ID. This
    # will remove the node and also remove all edges connected to it.
    #
    #     myGraph.removeNode 'Read'
    #
    # Once the node has been removed, the `removeNode` event will be
    # emitted.
    removeNode: (id) ->
        node =
            id: id

        for edge in @edges
            if edge.from.node is node.id
                @removeEdge edge
            if edge.to.node is node.id
                @removeEdge edge

        for initializer in @initializers
            if initializer.to.node is node.id
                @removeEdge initializer.to.node, initializer.to.port

        @emit 'removeNode', node

        if -1 isnt @nodes.indexOf node
            @nodes.splice @nodes.indexOf(node), 1

    # ## Getting a node
    #
    # Nodes objects can be retrieved from the graph by their ID:
    #
    #     myNode = myGraph.getNode 'Read'
    getNode: (id) ->
        for node in @nodes
            return node if node.id is id

    # ## Connecting nodes
    #
    # Nodes can be connected by adding edges between a node's outport
    # and another node's inport:
    #
    #     myGraph.addEdge 'Read', 'out', 'Display', 'in'
    #
    # Adding an edge will emit the `addEdge` event.
    addEdge: (outNode, outPort, inNode, inPort) ->
        edge =
            from:
                node: outNode
                port: outPort
            to:
                node: inNode
                port: inPort
        @edges.push edge
        @emit 'addEdge', edge

    # ## Disconnected nodes
    #
    # Connections between nodes can be removed by providing the
    # node and port to disconnect. The specified node and port can
    # be either the outport or the inport of the connection:
    #
    #     myGraph.removeEdge 'Read', 'out'
    #
    # or:
    #
    #     myGraph.removeEdge 'Display', 'in'
    #
    # Removing a connection will emit the `removeEdge` event.
    removeEdge: (node, port) ->
        for edge,index in @edges
            if edge.from.node is node and edge.from.port is port
                @emit 'removeEdge', edge
                @edges.splice index, 1
            if edge.to.node is node and edge.to.port is port
                @emit 'removeEdge', edge
                @edges.splice index, 1

        for edge,index in @initializers
            if edge.to.node is node and edge.to.port is port
                @emit 'removeEdge', edge
                @initializers.splice index, 1

    # ## Adding Initial Information Packets
    #
    # Initial Information Packets (IIPs) can be used for sending data
    # to specified node inports without a sending node instance.
    #
    # IIPs are especially useful for sending configuration information
    # to components at NoFlo network start-up time. This could include
    # filenames to read, or network ports to listen to.
    #
    #     myGraph.addInitial 'somefile.txt', 'Read', 'source'
    #
    # Adding an IIP will emit a `addEdge` event.
    addInitial: (data, node, port) ->
        initializer =
            from:
                data: data
            to:
                node: node
                port: port
        @initializers.push initializer
        @emit 'addEdge', initializer

    toDOT: ->
        cleanID = (id) ->
            id.replace /\s*/g, ""
        cleanPort = (port) ->
            port.replace /\./g, ""

        dot = "digraph {\n"

        for node in @nodes
            dot += "    #{cleanID(node.id)} [shape=box]\n"

        for initializer, id in @initializers
            dot += "    data#{id} -> #{cleanID(initializer.to.node)} [label='#{cleanPort(initializer.to.port)}']\n"

        for edge in @edges
            dot += "    #{cleanID(edge.from.node)} -> #{cleanID(edge.to.node)}[label='#{cleanPort(edge.from.port)}']\n"

        dot += "}"

        return dot

    toYUML: ->
        yuml = []

        for initializer in @initializers
            yuml.push "(start)[#{initializer.to.port}]->(#{initializer.to.node})"

        for edge in @edges
            yuml.push "(#{edge.from.node})[#{edge.from.port}]->(#{edge.to.node})"
        yuml.join ","

    toJSON: ->
        json =
            properties:
                name: @name
            processes: {}
            connections: []

        for node in @nodes
            json.processes[node.id] =
                component: node.component
            if node.display
                json.processes[node.id].display = node.display

        for edge in @edges
            json.connections.push
                src:
                    process: edge.from.node
                    port: edge.from.port
                tgt:
                    process: edge.to.node
                    port: edge.to.port

        for initializer in @initializers
            json.connections.push
                data: initializer.from.data
                tgt:
                    process: initializer.to.node
                    port: initializer.to.port

        json

    save: (file, success) ->
        json = JSON.stringify @toJSON(), null, 4
        fs.writeFile "#{file}.json", json, "utf-8", (err, data) ->
            throw err if err
            success file

exports.Graph = Graph

exports.createGraph = (name) ->
    new Graph name

exports.loadJSON = (definition, success) ->
    graph = new Graph definition.properties.name

    for id, def of definition.processes
        graph.addNode id, def.component, def.display

    for conn in definition.connections
        if conn.data
            graph.addInitial conn.data, conn.tgt.process, conn.tgt.port.toLowerCase()
            continue
        graph.addEdge conn.src.process, conn.src.port.toLowerCase(), conn.tgt.process, conn.tgt.port.toLowerCase()

    success graph

exports.loadFile = (file, success) ->
    fs.readFile file, "utf-8", (err, data) ->
        throw err if err

        if file.split('.').pop() is 'fbp'
            return exports.loadFBP data, success

        definition = JSON.parse data
        exports.loadJSON definition, success

exports.loadFBP = (fbpData, success) ->
    parser = new fbp.Fbp
    definition = parser.parse fbpData
    exports.loadJSON definition, success
