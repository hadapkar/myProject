import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import FORM_FACTOR from '@salesforce/client/formFactor';

import listUsers from '@salesforce/apex/SubscriptionAdminController.listUsers';
import updateSubscriptionDates from '@salesforce/apex/SubscriptionAdminController.updateSubscriptionDates';
import syncUsers from '@salesforce/apex/SubscriptionAdminController.syncUsers';
import freezeUsers from '@salesforce/apex/SubscriptionAdminController.freezeUsers';
import unfreezeUsers from '@salesforce/apex/SubscriptionAdminController.unfreezeUsers';

const COLUMNS = [
    {
        label: 'User',
        fieldName: 'userUrl',
        type: 'url',
        typeAttributes: { label: { fieldName: 'name' }, target: '_blank' }
    },
    { label: 'Username', fieldName: 'username', type: 'text' },
    { label: 'Active', fieldName: 'isActive', type: 'boolean' },
    {
        label: 'Subscription End',
        fieldName: 'subscriptionEndDate',
        type: 'date',
        editable: true,
        typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
    },
    { label: 'Subscription Active', fieldName: 'isSubscriptionActive', type: 'boolean' },
    { label: 'Frozen', fieldName: 'isFrozen', type: 'boolean' }
];

const SMALL_COLUMNS = [
    {
        label: 'User',
        fieldName: 'userUrl',
        type: 'url',
        wrapText: true,
        typeAttributes: { label: { fieldName: 'name' }, target: '_blank' }
    },
    {
        label: 'Subscription End',
        fieldName: 'subscriptionEndDate',
        type: 'date',
        editable: true,
        typeAttributes: { year: 'numeric', month: '2-digit', day: '2-digit' }
    },
    { label: 'Active', fieldName: 'isSubscriptionActive', type: 'boolean' },
    { label: 'Frozen', fieldName: 'isFrozen', type: 'boolean' }
];

export default class SubscriptionAdmin extends LightningElement {
    columns = FORM_FACTOR === 'Small' ? SMALL_COLUMNS : COLUMNS;

    @track rows = [];
    @track draftValues = [];

    searchKey = '';
    isLoading = false;
    selectedRowIds = [];
    bulkSubscriptionEndDate = null;

    connectedCallback() {
        this.refresh();
    }

    get disableSyncSelected() {
        return !this.selectedRowIds || this.selectedRowIds.length === 0 || this.isLoading;
    }

    get disableApplyDate() {
        return (
            this.disableSyncSelected ||
            !this.bulkSubscriptionEndDate
        );
    }

    get showRowNumbers() {
        return FORM_FACTOR !== 'Small';
    }

    handleSearchKeyChange(event) {
        this.searchKey = event.target.value;
        window.clearTimeout(this._searchDebounce);
        this._searchDebounce = window.setTimeout(() => this.refresh(), 300);
    }

    handleRefresh() {
        this.refresh();
    }

    handleRowSelection(event) {
        const selectedRows = event.detail.selectedRows || [];
        this.selectedRowIds = selectedRows.map((r) => r.id);
    }

    handleBulkDateChange(event) {
        this.bulkSubscriptionEndDate = event.target.value;
    }

    async handleSave(event) {
        const draftValues = event.detail.draftValues || [];
        if (draftValues.length === 0) {
            return;
        }

        const updates = draftValues.map((dv) => ({
            userId: dv.id,
            subscriptionEndDate: dv.subscriptionEndDate || null
        }));

        this.isLoading = true;
        try {
            const result = await updateSubscriptionDates({ updates, runSync: true });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Saved',
                    message: `Updated ${updates.length} user(s). Sync: frozen ${result.frozenCount}, unfrozen ${result.unfrozenCount}`,
                    variant: 'success'
                })
            );
            this.draftValues = [];
            await this.refresh();
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleApplyDateToSelected() {
        if (!this.selectedRowIds || this.selectedRowIds.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Select users',
                    message: 'Select one or more users first.',
                    variant: 'warning'
                })
            );
            return;
        }

        if (!this.bulkSubscriptionEndDate) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Choose a date',
                    message: 'Pick a subscription end date first.',
                    variant: 'warning'
                })
            );
            return;
        }

        const updates = this.selectedRowIds.map((id) => ({
            userId: id,
            subscriptionEndDate: this.bulkSubscriptionEndDate
        }));

        this.isLoading = true;
        try {
            const result = await updateSubscriptionDates({ updates, runSync: true });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Updated',
                    message: `Applied ${this.bulkSubscriptionEndDate} to ${updates.length} user(s). Sync: frozen ${result.frozenCount}, unfrozen ${result.unfrozenCount}`,
                    variant: 'success'
                })
            );
            const selected = new Set(this.selectedRowIds);
            this.rows = (this.rows || []).map((r) =>
                selected.has(r.id) ? { ...r, subscriptionEndDate: this.bulkSubscriptionEndDate } : r
            );
            this.draftValues = [];
            await this.refresh();
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleClearDateForSelected() {
        if (!this.selectedRowIds || this.selectedRowIds.length === 0) {
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Select users',
                    message: 'Select one or more users first.',
                    variant: 'warning'
                })
            );
            return;
        }

        const updates = this.selectedRowIds.map((id) => ({
            userId: id,
            subscriptionEndDate: null
        }));

        this.isLoading = true;
        try {
            const result = await updateSubscriptionDates({ updates, runSync: true });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Cleared',
                    message: `Cleared date for ${updates.length} user(s). Sync: frozen ${result.frozenCount}, unfrozen ${result.unfrozenCount}`,
                    variant: 'success'
                })
            );
            this.bulkSubscriptionEndDate = null;
            const selected = new Set(this.selectedRowIds);
            this.rows = (this.rows || []).map((r) =>
                selected.has(r.id) ? { ...r, subscriptionEndDate: null } : r
            );
            this.draftValues = [];
            await this.refresh();
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleSyncSelected() {
        this.isLoading = true;
        try {
            const result = await syncUsers({ userIds: this.selectedRowIds });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Synced',
                    message: `Frozen ${result.frozenCount}, unfrozen ${result.unfrozenCount}`,
                    variant: 'success'
                })
            );
            await this.refresh();
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleFreezeSelected() {
        this.isLoading = true;
        try {
            const updated = await freezeUsers({ userIds: this.selectedRowIds });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Frozen',
                    message: `Frozen ${updated} user(s).`,
                    variant: 'success'
                })
            );
            await this.refresh();
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async handleUnfreezeSelected() {
        this.isLoading = true;
        try {
            const updated = await unfreezeUsers({ userIds: this.selectedRowIds });
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Unfrozen',
                    message: `Unfrozen ${updated} user(s).`,
                    variant: 'success'
                })
            );
            await this.refresh();
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    async refresh() {
        this.isLoading = true;
        try {
            this.rows = await listUsers({ searchKey: this.searchKey, limitSize: 200 });
        } catch (e) {
            this.showError(e);
        } finally {
            this.isLoading = false;
        }
    }

    showError(error) {
        const message =
            error?.body?.message ||
            error?.message ||
            'Unexpected error';

        this.dispatchEvent(
            new ShowToastEvent({
                title: 'Error',
                message,
                variant: 'error'
            })
        );
    }
}
