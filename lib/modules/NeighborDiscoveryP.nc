
#include <Timer.h>
#include "../../includes/channels.h"
#include "../../includes/packet.h"
#include "../../includes/protocol.h"
#include "../../includes/channels.h"

#define NODETIMETOLIVE  5  // Time to live for each neighbor

module NeighborDiscoveryP {
    provides interface NeighborDiscovery;
    uses interface Random as Random;
    uses interface Timer<TMilli> as Timer;
    uses interface Hashmap<uint32_t> as NeighborTable;
    uses interface SimpleSend as Sender;
    uses interface LinkStateRouting as LinkStateRouting;  // Added for Project 4

}

implementation {

    pack sendp;  // Packet for sending neighbor pings
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length);

    // Start neighbor discovery with a periodic timer
    command error_t NeighborDiscovery.start() {
        call Timer.startPeriodic(500 + (uint16_t)(call Random.rand16() % 500));  // Periodic timer with random offset
        dbg(GENERAL_CHANNEL, "Node %d: Began Neighbor Discovery\n", TOS_NODE_ID);
        return SUCCESS;
    }

    // Process incoming discovery packets
    command void NeighborDiscovery.discover(pack* packet) {
        if (packet->TTL > 0 && packet->protocol == PROTOCOL_PING) {
            dbg(GENERAL_CHANNEL, "PING Neighbor Discovery\n");
            packet->TTL -= 1;
            packet->src = TOS_NODE_ID;
            packet->protocol = PROTOCOL_PINGREPLY;

           
        }
        else if (packet->protocol == PROTOCOL_PINGREPLY && packet->dest == 0) {
            dbg(GENERAL_CHANNEL, "PING REPLY Neighbor Discovery, Confirmed neighbor %d\n", packet->src);
            if (!call NeighborTable.contains(packet->src)) {
                call NeighborTable.insert(packet->src, NODETIMETOLIVE);
                // Notify Link State Routing
                call LinkStateRouting.handleNeighborFound();
            } else {
                // Refresh TTL if neighbor is already known
                call NeighborTable.insert(packet->src, NODETIMETOLIVE);
            }
        }
    }

    // Timer event to periodically send PINGs and prune inactive neighbors
    event void Timer.fired() {
        uint32_t* neighbors = call NeighborTable.getKeys();
        uint16_t i = 0;
        uint8_t payload = 0;

        // Prune inactive neighbors
        for (i = 0; i < call NeighborTable.size(); i++) {
            if (neighbors[i] == 0) {
                continue;  // Skip if neighbor ID is invalid
            }

            // If TTL expired, remove the neighbor
            if (call NeighborTable.get(neighbors[i]) == 0) {
                dbg(GENERAL_CHANNEL, "Deleted Neighbor %d (TTL expired)\n", neighbors[i]);
                call NeighborTable.remove(neighbors[i]);
                call LinkStateRouting.handleNeighborLost(neighbors[i]);  // Notify Link State Routing of lost neighbor
            } else {
                // Decrease TTL for remaining neighbors
                call NeighborTable.insert(neighbors[i], call NeighborTable.get(neighbors[i]) - 1);
            }
        }

        // Send PING to discover neighbors
        makePack(&sendp, TOS_NODE_ID, 0, 1, PROTOCOL_PING, 0, &payload, PACKET_MAX_PAYLOAD_SIZE);
        call Sender.send(sendp, AM_BROADCAST_ADDR);  // Broadcast PING packet
    }

    // Utility function to create packets
    void makePack(pack *Package, uint16_t src, uint16_t dest, uint16_t TTL, uint16_t protocol, uint16_t seq, uint8_t* payload, uint8_t length) {
        Package->src = src;
        Package->dest = dest;
        Package->TTL = TTL;
        Package->seq = seq;
        Package->protocol = protocol;
        memcpy(Package->payload, payload, length);
    }

    // Get list of neighbors
    command uint32_t* NeighborDiscovery.getNeighbors() {
        return call NeighborTable.getKeys();
    }

    // Get size of the neighbor list
    command uint16_t NeighborDiscovery.getNeighborListSize() {
        return call NeighborTable.size();
    }

    // Print list of neighbors and the node's ID
    command void NeighborDiscovery.printNeighbors() {
        uint16_t i = 0;
        uint32_t* neighbors = call NeighborTable.getKeys();
        uint16_t numNeighbors = call NeighborTable.size();

        dbg(GENERAL_CHANNEL, "Node %d has the following neighbors:\n", TOS_NODE_ID);

        if (numNeighbors == 0) {
            dbg(GENERAL_CHANNEL, "\tNo neighbors found.\n");
        } else {
            for (i = 0; i < numNeighbors; i++) {
                if (neighbors[i] != 0) {
                    dbg(GENERAL_CHANNEL, "\tNeighbor: %d\n", neighbors[i]);
                }
            }
        }
    }
}

