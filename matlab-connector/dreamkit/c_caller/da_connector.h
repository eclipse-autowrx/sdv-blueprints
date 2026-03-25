#ifndef DA_CONNECTOR_H
#define DA_CONNECTOR_H

#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

// Read functions - Get values from DA via UDS
double da_get_pothole_left();
double da_get_pothole_center();
double da_get_pothole_right();
double da_get_steering_angle();

// Write function - Set hazard signal to DA via UDS
void da_set_hazard_signal(bool value);

#ifdef __cplusplus
}
#endif

#endif // DA_CONNECTOR_H
