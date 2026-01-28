"""
Transaction Analysis Module
============================

Core functionality for analyzing digital payment transaction data.
Includes adoption metrics, trend analysis, and channel performance evaluation.

Author: Your Name
Date: 2025-01-27
"""

import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional
import warnings

warnings.filterwarnings('ignore')


class TransactionAnalyzer:
    """
    Main class for transaction data analysis.
    
    Provides methods for calculating adoption metrics, identifying trends,
    and generating insights from payment transaction data.
    """
    
    def __init__(self, data_source: str or pd.DataFrame, date_column: str = 'transaction_date'):
        """
        Initialize the analyzer with transaction data.
        
        Parameters:
        -----------
        data_source : str or pd.DataFrame
            Path to CSV file or DataFrame containing transaction data
        date_column : str
            Name of the date column in the dataset
        """
        if isinstance(data_source, str):
            self.transactions = pd.read_csv(data_source)
        else:
            self.transactions = data_source.copy()
        
        self.date_column = date_column
        self._prepare_data()
    
    def _prepare_data(self):
        """Prepare and validate transaction data."""
        # Convert date column to datetime
        self.transactions[self.date_column] = pd.to_datetime(
            self.transactions[self.date_column]
        )
        
        # Sort by date
        self.transactions = self.transactions.sort_values(self.date_column)
        
        # Extract date components
        self.transactions['year'] = self.transactions[self.date_column].dt.year
        self.transactions['month'] = self.transactions[self.date_column].dt.month
        self.transactions['quarter'] = self.transactions[self.date_column].dt.quarter
        self.transactions['day_of_week'] = self.transactions[self.date_column].dt.dayofweek
        self.transactions['week'] = self.transactions[self.date_column].dt.isocalendar().week
        
        print(f"Loaded {len(self.transactions):,} transactions")
        print(f"Date range: {self.transactions[self.date_column].min()} to {self.transactions[self.date_column].max()}")
    
    def calculate_adoption_metrics(self, 
                                   group_by: str = 'month',
                                   channel_column: str = 'channel') -> pd.DataFrame:
        """
        Calculate key adoption metrics over time.
        
        Parameters:
        -----------
        group_by : str
            Grouping period ('day', 'week', 'month', 'quarter')
        channel_column : str
            Column name for payment channel
        
        Returns:
        --------
        pd.DataFrame
            Adoption metrics by time period
        """
        # Create period column
        if group_by == 'day':
            self.transactions['period'] = self.transactions[self.date_column].dt.date
        elif group_by == 'week':
            self.transactions['period'] = self.transactions[self.date_column].dt.to_period('W')
        elif group_by == 'month':
            self.transactions['period'] = self.transactions[self.date_column].dt.to_period('M')
        elif group_by == 'quarter':
            self.transactions['period'] = self.transactions[self.date_column].dt.to_period('Q')
        
        # Calculate metrics
        metrics = self.transactions.groupby('period').agg({
            'transaction_id': 'count',
            'user_id': 'nunique',
            'amount': ['sum', 'mean', 'median'],
            channel_column: lambda x: x.nunique()
        }).reset_index()
        
        # Flatten column names
        metrics.columns = [
            'period', 'transaction_count', 'active_users', 
            'total_value', 'avg_transaction_value', 'median_transaction_value',
            'channels_used'
        ]
        
        # Calculate growth rates
        metrics['transaction_growth'] = metrics['transaction_count'].pct_change() * 100
        metrics['user_growth'] = metrics['active_users'].pct_change() * 100
        metrics['value_growth'] = metrics['total_value'].pct_change() * 100
        
        # Calculate transactions per user
        metrics['transactions_per_user'] = (
            metrics['transaction_count'] / metrics['active_users']
        )
        
        return metrics
    
    def analyze_channel_performance(self, 
                                   channel_column: str = 'channel',
                                   top_n: int = None) -> pd.DataFrame:
        """
        Analyze performance by payment channel.
        
        Parameters:
        -----------
        channel_column : str
            Column name for payment channel
        top_n : int, optional
            Return only top N channels by transaction count
        
        Returns:
        --------
        pd.DataFrame
            Channel performance metrics
        """
        channel_metrics = self.transactions.groupby(channel_column).agg({
            'transaction_id': 'count',
            'user_id': 'nunique',
            'amount': ['sum', 'mean', 'median']
        }).reset_index()
        
        # Flatten columns
        channel_metrics.columns = [
            'channel', 'transaction_count', 'unique_users',
            'total_value', 'avg_value', 'median_value'
        ]
        
        # Calculate percentages
        total_transactions = channel_metrics['transaction_count'].sum()
        total_value = channel_metrics['total_value'].sum()
        
        channel_metrics['pct_transactions'] = (
            channel_metrics['transaction_count'] / total_transactions * 100
        )
        channel_metrics['pct_value'] = (
            channel_metrics['total_value'] / total_value * 100
        )
        
        # Sort by transaction count
        channel_metrics = channel_metrics.sort_values(
            'transaction_count', ascending=False
        )
        
        if top_n:
            channel_metrics = channel_metrics.head(top_n)
        
        return channel_metrics
    
    def calculate_user_lifetime_metrics(self, 
                                        user_column: str = 'user_id',
                                        lookback_days: int = 365) -> pd.DataFrame:
        """
        Calculate lifetime metrics for each user.
        
        Parameters:
        -----------
        user_column : str
            Column name for user identifier
        lookback_days : int
            Number of days to look back for analysis
        
        Returns:
        --------
        pd.DataFrame
            User lifetime metrics
        """
        # Filter to lookback period
        cutoff_date = self.transactions[self.date_column].max() - timedelta(days=lookback_days)
        recent_data = self.transactions[
            self.transactions[self.date_column] >= cutoff_date
        ]
        
        # Calculate per-user metrics
        user_metrics = recent_data.groupby(user_column).agg({
            'transaction_id': 'count',
            'amount': ['sum', 'mean'],
            self.date_column: ['min', 'max'],
            'channel': lambda x: x.nunique()
        }).reset_index()
        
        # Flatten columns
        user_metrics.columns = [
            'user_id', 'transaction_count', 'total_spent', 'avg_transaction',
            'first_transaction', 'last_transaction', 'channels_used'
        ]
        
        # Calculate recency (days since last transaction)
        max_date = recent_data[self.date_column].max()
        user_metrics['recency_days'] = (
            max_date - user_metrics['last_transaction']
        ).dt.days
        
        # Calculate tenure (days from first to last transaction)
        user_metrics['tenure_days'] = (
            user_metrics['last_transaction'] - user_metrics['first_transaction']
        ).dt.days
        
        return user_metrics
    
    def identify_growth_opportunities(self, 
                                     segment_columns: List[str],
                                     min_segment_size: int = 100) -> pd.DataFrame:
        """
        Identify segments with growth opportunities based on adoption gaps.
        
        Parameters:
        -----------
        segment_columns : List[str]
            Columns to segment by (e.g., ['region', 'age_group'])
        min_segment_size : int
            Minimum number of users in segment to include
        
        Returns:
        --------
        pd.DataFrame
            Segments ranked by opportunity
        """
        # Calculate overall adoption rate
        total_users = self.transactions['user_id'].nunique()
        total_transactions = len(self.transactions)
        overall_avg_transactions = total_transactions / total_users
        
        # Calculate by segment
        segment_metrics = self.transactions.groupby(segment_columns).agg({
            'user_id': 'nunique',
            'transaction_id': 'count',
            'amount': 'sum'
        }).reset_index()
        
        segment_metrics.columns = list(segment_columns) + [
            'user_count', 'transaction_count', 'total_value'
        ]
        
        # Filter by minimum size
        segment_metrics = segment_metrics[
            segment_metrics['user_count'] >= min_segment_size
        ]
        
        # Calculate opportunity metrics
        segment_metrics['transactions_per_user'] = (
            segment_metrics['transaction_count'] / segment_metrics['user_count']
        )
        
        segment_metrics['gap_vs_average'] = (
            overall_avg_transactions - segment_metrics['transactions_per_user']
        )
        
        segment_metrics['opportunity_score'] = (
            segment_metrics['gap_vs_average'] * segment_metrics['user_count']
        )
        
        # Sort by opportunity
        segment_metrics = segment_metrics.sort_values(
            'opportunity_score', ascending=False
        )
        
        return segment_metrics
    
    def calculate_cohort_retention(self, 
                                   cohort_period: str = 'month',
                                   periods_to_track: int = 12) -> pd.DataFrame:
        """
        Calculate cohort-based retention analysis.
        
        Parameters:
        -----------
        cohort_period : str
            Period for cohort definition ('month', 'quarter')
        periods_to_track : int
            Number of periods to track retention
        
        Returns:
        --------
        pd.DataFrame
            Cohort retention matrix
        """
        # Get first transaction per user
        first_transaction = self.transactions.groupby('user_id')[
            self.date_column
        ].min().reset_index()
        first_transaction.columns = ['user_id', 'first_transaction_date']
        
        # Merge back to transactions
        cohort_data = self.transactions.merge(
            first_transaction, on='user_id', how='left'
        )
        
        # Define cohort period
        if cohort_period == 'month':
            cohort_data['cohort'] = cohort_data['first_transaction_date'].dt.to_period('M')
            cohort_data['transaction_period'] = cohort_data[self.date_column].dt.to_period('M')
        elif cohort_period == 'quarter':
            cohort_data['cohort'] = cohort_data['first_transaction_date'].dt.to_period('Q')
            cohort_data['transaction_period'] = cohort_data[self.date_column].dt.to_period('Q')
        
        # Calculate period number
        cohort_data['period_number'] = (
            cohort_data['transaction_period'] - cohort_data['cohort']
        ).apply(lambda x: x.n)
        
        # Create retention matrix
        retention = cohort_data.groupby(['cohort', 'period_number'])[
            'user_id'
        ].nunique().reset_index()
        
        retention_pivot = retention.pivot(
            index='cohort', 
            columns='period_number', 
            values='user_id'
        )
        
        # Calculate retention percentages
        cohort_sizes = retention_pivot.iloc[:, 0]
        retention_pct = retention_pivot.div(cohort_sizes, axis=0) * 100
        
        return retention_pct.iloc[:, :periods_to_track]
    
    def generate_summary_statistics(self) -> Dict:
        """
        Generate summary statistics for executive reporting.
        
        Returns:
        --------
        Dict
            Summary statistics and KPIs
        """
        total_transactions = len(self.transactions)
        total_users = self.transactions['user_id'].nunique()
        total_value = self.transactions['amount'].sum()
        
        # Date range
        min_date = self.transactions[self.date_column].min()
        max_date = self.transactions[self.date_column].max()
        days_span = (max_date - min_date).days
        
        # Recent metrics (last 30 days)
        last_30_days = max_date - timedelta(days=30)
        recent_data = self.transactions[
            self.transactions[self.date_column] >= last_30_days
        ]
        
        summary = {
            'total_transactions': total_transactions,
            'total_users': total_users,
            'total_value': total_value,
            'avg_transaction_value': total_value / total_transactions,
            'transactions_per_user': total_transactions / total_users,
            'date_range': f"{min_date.date()} to {max_date.date()}",
            'days_analyzed': days_span,
            'channels': self.transactions['channel'].nunique(),
            'last_30_days': {
                'transactions': len(recent_data),
                'active_users': recent_data['user_id'].nunique(),
                'value': recent_data['amount'].sum(),
                'daily_avg_transactions': len(recent_data) / 30
            }
        }
        
        return summary
    
    def export_to_excel(self, filepath: str, include_sections: List[str] = None):
        """
        Export analysis results to Excel file.
        
        Parameters:
        -----------
        filepath : str
            Output file path
        include_sections : List[str], optional
            Sections to include in export
        """
        with pd.ExcelWriter(filepath, engine='openpyxl') as writer:
            # Summary statistics
            if not include_sections or 'summary' in include_sections:
                summary = self.generate_summary_statistics()
                summary_df = pd.DataFrame([summary]).T
                summary_df.columns = ['Value']
                summary_df.to_excel(writer, sheet_name='Summary')
            
            # Adoption metrics
            if not include_sections or 'adoption' in include_sections:
                adoption = self.calculate_adoption_metrics()
                adoption.to_excel(writer, sheet_name='Adoption Metrics', index=False)
            
            # Channel performance
            if not include_sections or 'channels' in include_sections:
                channels = self.analyze_channel_performance()
                channels.to_excel(writer, sheet_name='Channel Performance', index=False)
            
            # User metrics
            if not include_sections or 'users' in include_sections:
                users = self.calculate_user_lifetime_metrics()
                users.to_excel(writer, sheet_name='User Metrics', index=False)
        
        print(f"Analysis exported to {filepath}")


# Helper functions for data generation (for testing)
def generate_sample_data(n_transactions: int = 10000,
                        n_users: int = 1000,
                        start_date: str = '2023-01-01',
                        end_date: str = '2024-12-31') -> pd.DataFrame:
    """
    Generate sample transaction data for testing.
    
    Parameters:
    -----------
    n_transactions : int
        Number of transactions to generate
    n_users : int
        Number of unique users
    start_date : str
        Start date for transaction range
    end_date : str
        End date for transaction range
    
    Returns:
    --------
    pd.DataFrame
        Sample transaction data
    """
    np.random.seed(42)
    
    # Date range
    dates = pd.date_range(start=start_date, end=end_date, freq='H')
    
    # Channels with realistic distribution
    channels = ['mobile_app', 'web_portal', 'pos_terminal', 'peer_to_peer']
    channel_weights = [0.45, 0.25, 0.20, 0.10]
    
    # Transaction types
    transaction_types = ['purchase', 'transfer', 'bill_payment', 'withdrawal']
    
    # Generate data
    data = {
        'transaction_id': [f'TXN{str(i).zfill(8)}' for i in range(n_transactions)],
        'user_id': np.random.choice([f'USER{str(i).zfill(6)}' for i in range(n_users)], n_transactions),
        'transaction_date': np.random.choice(dates, n_transactions),
        'channel': np.random.choice(channels, n_transactions, p=channel_weights),
        'transaction_type': np.random.choice(transaction_types, n_transactions),
        'amount': np.random.lognormal(3.5, 1.2, n_transactions),  # Log-normal distribution
        'status': np.random.choice(['completed', 'pending', 'failed'], n_transactions, p=[0.95, 0.03, 0.02]),
        'merchant_category': np.random.choice(
            ['retail', 'food', 'entertainment', 'utilities', 'healthcare', 'other'],
            n_transactions
        )
    }
    
    df = pd.DataFrame(data)
    df['amount'] = df['amount'].round(2)
    
    return df


if __name__ == '__main__':
    # Example usage
    print("Generating sample transaction data...")
    sample_data = generate_sample_data(n_transactions=50000, n_users=5000)
    
    print("\nInitializing analyzer...")
    analyzer = TransactionAnalyzer(sample_data)
    
    print("\nCalculating adoption metrics...")
    adoption = analyzer.calculate_adoption_metrics(group_by='month')
    print(adoption.head())
    
    print("\nAnalyzing channel performance...")
    channels = analyzer.analyze_channel_performance()
    print(channels)
    
    print("\nGenerating summary statistics...")
    summary = analyzer.generate_summary_statistics()
    for key, value in summary.items():
        print(f"{key}: {value}")
