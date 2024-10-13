

#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"

// Link state constants
#define LS_MAX_ROUTES 256
#define LS_MAX_COST 17
#define LS_TTL 17

module LinkStateRoutingP {
    provides interface LinkStateRouting;
    
    uses interface SimpleSend as Sender;
    uses interface MapList<uint16_t, uint16_t> as PacketsReceived;
    uses interface NeighborDiscovery as NeighborDiscovery;
    uses interface Flooding as Flooding;
    uses interface Timer<TMilli> as LSRTimer;
    uses interface Random as Random;
}

implementation {

    typedef struct {
        uint8_t nextHop;
        uint8_t cost;
    } Route;

    typedef struct {
        uint8_t neighbor;
        uint8_t cost;
    } LSP;

    uint8_t linkState[LS_MAX_ROUTES][LS_MAX_ROUTES];
    Route routingTable[LS_MAX_ROUTES];
    uint16_t numKnownNodes = 0;
    uint16_t numRoutes = 0;
    uint16_t sequenceNum = 0;
    pack routePack;

    // Function prototypes
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length);
    void initializeRoutingTable();
    bool updateState(pack* myMsg);
    bool updateRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost);
    void removeRoute(uint8_t dest);
    void sendLSP(uint8_t lostNeighbor);
    void handleForward(pack* myMsg);
    void dijkstra();

    // Start LinkStateRouting
    command error_t LinkStateRouting.start() {
        dbg(GENERAL_CHANNEL, "Link State Routing started on node %u!\n", TOS_NODE_ID);
        initializeRoutingTable();
        call LSRTimer.startOneShot(40000);
        return SUCCESS;
    }

    // LSRTimer fired
    event void LSRTimer.fired() {
        if (call LSRTimer.isOneShot()) {
            call LSRTimer.startPeriodic(30000 + (uint16_t)(call Random.rand16() % 5000));
        } else {
            sendLSP(0);
        }
    }

    // Send Ping
    command void LinkStateRouting.ping(uint16_t destination, uint8_t *payload) {
        makePack(&routePack, TOS_NODE_ID, destination, 0, PROTOCOL_PING, 0, payload, PACKET_MAX_PAYLOAD_SIZE);
        dbg(GENERAL_CHANNEL, "PING for LSA from %d to %d\n", TOS_NODE_ID, destination);
        call LinkStateRouting.routePacket(&routePack);

    }

    // Route packet
    command void LinkStateRouting.routePacket(pack* myMsg) {
        uint8_t nextHop;

        if (myMsg->dest == TOS_NODE_ID) {
            if (myMsg->protocol == PROTOCOL_PING) {
                dbg(GENERAL_CHANNEL, "Packet routed via LINK STATE ROUTING and reached destination %d!\n", TOS_NODE_ID);
                makePack(&routePack, myMsg->dest, myMsg->src, 0, PROTOCOL_PINGREPLY, 0, (uint8_t *)myMsg->payload, PACKET_MAX_PAYLOAD_SIZE);
                call LinkStateRouting.routePacket(&routePack);
            } else if (myMsg->protocol == PROTOCOL_PINGREPLY) {
                dbg(GENERAL_CHANNEL, "PING_REPLY reached destination %d!\n", TOS_NODE_ID);
            }
            return;
        }

        if (routingTable[myMsg->dest].cost < LS_MAX_COST) {
            nextHop = routingTable[myMsg->dest].nextHop;
            dbg(GENERAL_CHANNEL, "Node %d routing packet through %d\n", TOS_NODE_ID, nextHop);
            dbg(GENERAL_CHANNEL, "This is pring out node and it's route \n");
            call Sender.send(*myMsg, nextHop);
        } else {
            dbg(GENERAL_CHANNEL, "No route to destination. Dropping packet...\n");
        }
    }

    // Handle Link-State packet
    command void LinkStateRouting.handleLS(pack* myMsg) {
        if (myMsg->src == TOS_NODE_ID || call PacketsReceived.containsVal(myMsg->src, myMsg->seq)) {
            return;
        } else {
            call PacketsReceived.insertVal(myMsg->src, myMsg->seq);
        }

        if (updateState(myMsg)) {
            dijkstra();
        }

        // Forward to all neighbors
        call Sender.send(*myMsg, AM_BROADCAST_ADDR);
    }

    // Handle Neighbor Lost
    command void LinkStateRouting.handleNeighborLost(uint16_t lostNeighbor) {
        dbg(GENERAL_CHANNEL, "Neighbor lost %u\n", lostNeighbor);
        if (linkState[TOS_NODE_ID][lostNeighbor] != LS_MAX_COST) {
            linkState[TOS_NODE_ID][lostNeighbor] = LS_MAX_COST;
            linkState[lostNeighbor][TOS_NODE_ID] = LS_MAX_COST;
            numKnownNodes--;
            removeRoute(lostNeighbor);
        }
        sendLSP(lostNeighbor);
        dijkstra();
    }

    // Handle Neighbor Found
    command void LinkStateRouting.handleNeighborFound() {
        dbg(GENERAL_CHANNEL, "This is handling neighbor fround \n");
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint16_t i;

        for (i = 0; i < neighborsListSize; i++) {
            linkState[TOS_NODE_ID][neighbors[i]] = 1;
            linkState[neighbors[i]][TOS_NODE_ID] = 1;
        }
        sendLSP(0);
        dijkstra();
    }

    // Print Routing Table
    command void LinkStateRouting.printRouteTable() {
        dbg(GENERAL_CHANNEL, "this is print rout table \n");
        uint16_t i;
        dbg(GENERAL_CHANNEL, "DEST  HOP  COST\n");
        for (i = 1; i < LS_MAX_ROUTES; i++) {
            if (routingTable[i].cost != LS_MAX_COST) {
                dbg(GENERAL_CHANNEL, "%4d%5d%6d\n", i, routingTable[i].nextHop, routingTable[i].cost);
            }
        }
    }

    // Initialize Routing Table
    void initializeRoutingTable() {
        uint16_t i, j;
        for (i = 0; i < LS_MAX_ROUTES; i++) {
            routingTable[i].nextHop = 0;
            routingTable[i].cost = LS_MAX_COST;
        }
        for (i = 0; i < LS_MAX_ROUTES; i++) {
            for (j = 0; j < LS_MAX_ROUTES; j++) {
                linkState[i][j] = LS_MAX_COST;
            }
        }
        routingTable[TOS_NODE_ID].nextHop = TOS_NODE_ID;
        routingTable[TOS_NODE_ID].cost = 0;
        linkState[TOS_NODE_ID][TOS_NODE_ID] = 0;
        numKnownNodes++;
        numRoutes++;
    }

    // Update state from received LSP
    bool updateState(pack* myMsg) {
        uint16_t i;
        LSP *lsp = (LSP *)myMsg->payload;
        bool isStateUpdated = FALSE;

        for (i = 0; i < 10; i++) {
            if (linkState[myMsg->src][lsp[i].neighbor] != lsp[i].cost) {
                if (linkState[myMsg->src][lsp[i].neighbor] == LS_MAX_COST) {
                    numKnownNodes++;
                } else if (lsp[i].cost == LS_MAX_COST) {
                    numKnownNodes--;
                }
                linkState[myMsg->src][lsp[i].neighbor] = lsp[i].cost;
                linkState[lsp[i].neighbor][myMsg->src] = lsp[i].cost;
                isStateUpdated = TRUE;
            }
        }
        return isStateUpdated;
    }

    // Send LSP
    void sendLSP(uint8_t lostNeighbor) {
        uint32_t* neighbors = call NeighborDiscovery.getNeighbors();
        uint16_t neighborsListSize = call NeighborDiscovery.getNeighborListSize();
        uint16_t i = 0, counter = 0;
        LSP linkStatePayload[10];

        memset(linkStatePayload, 0, sizeof(linkStatePayload)); // Zero out the array

        // If neighbor lost, set infinite cost
        if (lostNeighbor != 0) {
            dbg(GENERAL_CHANNEL, "Sending out lost neighbor %u\n", lostNeighbor);
            linkStatePayload[counter].neighbor = lostNeighbor;
            linkStatePayload[counter].cost = LS_MAX_COST;
            counter++;
        }

        // Add neighbors in groups of 10 and flood LSP
        for (i = 0; i < neighborsListSize; i++) {
            linkStatePayload[counter].neighbor = neighbors[i];
            linkStatePayload[counter].cost = 1;
            counter++;

            if (counter == 10 || i == neighborsListSize - 1) {
                makePack(&routePack, TOS_NODE_ID, 0, LS_TTL, PROTOCOL_LS, sequenceNum++, &linkStatePayload, sizeof(linkStatePayload));
                call Sender.send(routePack, AM_BROADCAST_ADDR);
                memset(linkStatePayload, 0, sizeof(linkStatePayload)); // Zero the array
                counter = 0;
            }
        }
    }

    // Dijkstra's algorithm to update the routing table
    void dijkstra() {
        dbg(GENERAL_CHANNEL, "Starting dijstra algoritiom \n");
        uint16_t i;
        uint8_t currentNode = TOS_NODE_ID;
        uint8_t cost[LS_MAX_ROUTES];
        uint8_t prev[LS_MAX_ROUTES];
        bool visited[LS_MAX_ROUTES];
        uint8_t minCost, nextNode;
        uint16_t count = numKnownNodes;

        for (i = 0; i < LS_MAX_ROUTES; i++) {
            cost[i] = LS_MAX_COST;
            prev[i] = 0;
            visited[i] = FALSE;
        }
        cost[currentNode] = 0;

        while (count--) {
            // Find the unvisited node with the smallest cost
            minCost = LS_MAX_COST;
            nextNode = 0;
            for (i = 1; i < LS_MAX_ROUTES; i++) {
                if (!visited[i] && cost[i] < minCost) {
                    minCost = cost[i];
                    nextNode = i;
                }
            }
            currentNode = nextNode;
            visited[currentNode] = TRUE;

            // Update neighbors' cost
            for (i = 1; i < LS_MAX_ROUTES; i++) {
                if (linkState[currentNode][i] < LS_MAX_COST && !visited[i] && cost[currentNode] + linkState[currentNode][i] < cost[i]) {
                    cost[i] = cost[currentNode] + linkState[currentNode][i];
                    prev[i] = currentNode;
                }
            }
        }

        // Update routing table
        for (i = 1; i < LS_MAX_ROUTES; i++) {
            if (cost[i] != LS_MAX_COST) {
                uint8_t prevNode = i;
                while (prev[prevNode] != TOS_NODE_ID) {
                    prevNode = prev[prevNode];
                }
                addRoute(i, prevNode, cost[i]);
            } else {
                removeRoute(i);
            }
        }
    }

    // Add a route to the routing table
    void addRoute(uint8_t dest, uint8_t nextHop, uint8_t cost) {
        if (cost < routingTable[dest].cost) {
            routingTable[dest].nextHop = nextHop;
            routingTable[dest].cost = cost;
            numRoutes++;
        }
    }

    // Remove a route from the routing table
    void removeRoute(uint8_t dest) {
        routingTable[dest].nextHop = 0;
        routingTable[dest].cost = LS_MAX_COST;
        numRoutes--;
        dbg(GENERAL_CHANNEL, "reducing routing and number of routes %d," numRoutes);
    }

    // Make a packet
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, void* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }
}
